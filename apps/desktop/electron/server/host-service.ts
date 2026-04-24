import { randomUUID } from 'node:crypto'
import { once } from 'node:events'
import type { AddressInfo } from 'node:net'
import type { WebSocket } from 'ws'
import express from 'express'
import {
  createConnectApprovedMessage,
  createConnectRejectedMessage,
  createTextMessage,
  createTransferAcceptMessage,
  createTransferRejectMessage,
  stringifyQrPayload,
  type TransferItem,
  type ConnectRequestPayload,
  type TextMessagePayload,
  type TransferOfferPayload,
} from '@link-me/shared'
import { createHostServer } from './app'
import { ConnectionManager } from './connection-manager'
import { TransferManager } from './transfer-manager'
import { writeTransferFile } from './file-service'

interface HostServiceOptions {
  hostId: string
  hostName: string
  hostIp: string
  pairToken: string
  defaultSaveDirectory?: string
}

interface IncomingEnvelope {
  type: string
  payload?: ConnectRequestPayload | TextMessagePayload | TransferOfferPayload
}

export const createDesktopHostService = (options: HostServiceOptions) => {
  const hostServer = createHostServer()
  const connectionManager = new ConnectionManager()
  const transferManager = new TransferManager()
  const sockets = new Map<string, WebSocket>()
  const messages = new Map<string, TextMessagePayload[]>()
  let currentPort = 0

  const buildHostInfo = () => ({
    hostId: options.hostId,
    hostName: options.hostName,
    hostIp: options.hostIp,
    port: currentPort,
    qrPayload: stringifyQrPayload({
      version: 1,
      hostId: options.hostId,
      hostName: options.hostName,
      hostIp: options.hostIp,
      port: currentPort,
      pairToken: options.pairToken,
      expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    }),
  })

  const getSocketBySessionId = (sessionId: string) => {
    const session = connectionManager.findSessionById(sessionId)
    if (!session) {
      throw new Error('session not found')
    }

    return sockets.get(session.socketId)
  }

  hostServer.app.get('/api/host-info', (_req, res) => {
    res.json(buildHostInfo())
  })

  hostServer.app.post(
    '/api/transfers/:sessionId/:transferId/upload',
    express.raw({ type: 'application/octet-stream', limit: '100mb' }),
    async (req, res) => {
      const { sessionId, transferId } = req.params
      const transfer = transferManager.getTransfer(sessionId, transferId)

      if (!transfer || transfer.status === 'offered' || transfer.status === 'rejected' || !transfer.targetDirectory) {
        res.status(409).json({ error: 'transfer_not_accepted' })
        return
      }

      const relativePathHeader = req.header('x-relative-path')
      if (!relativePathHeader) {
        res.status(400).json({ error: 'missing_relative_path' })
        return
      }

      try {
        transferManager.markItemTransferring(sessionId, transferId, relativePathHeader)
        const body = Buffer.isBuffer(req.body) ? req.body : Buffer.from([])
        const savedPath = await writeTransferFile(transfer.targetDirectory, relativePathHeader, body)
        const nextTransfer = transferManager.markItemSucceeded(
          sessionId,
          transferId,
          relativePathHeader,
          savedPath,
          body.byteLength,
        )

        res.json({ ok: true, savedPath, transfer: nextTransfer })
      } catch (error) {
        transferManager.markItemFailed(
          sessionId,
          transferId,
          relativePathHeader,
          error instanceof Error ? error.message : 'upload_failed',
        )
        res.status(500).json({
          ok: false,
          error: error instanceof Error ? error.message : 'upload_failed',
        })
      }
    },
  )

  hostServer.websocket.on('connection', (socket) => {
    const socketId = randomUUID()
    sockets.set(socketId, socket)

    socket.on('message', (raw) => {
      const message = JSON.parse(raw.toString()) as IncomingEnvelope
      if (message.type === 'text_message' && message.payload) {
        const session = connectionManager.findSessionBySocketId(socketId)
        if (!session) {
          return
        }

        const textPayload = message.payload as TextMessagePayload
        const currentMessages = messages.get(session.sessionId) ?? []
        currentMessages.push(textPayload)
        messages.set(session.sessionId, currentMessages)
        return
      }

      if (message.type === 'transfer_offer' && message.payload) {
        const session = connectionManager.findSessionBySocketId(socketId)
        if (!session) {
          return
        }

        const payload = message.payload as TransferOfferPayload
        transferManager.createOffer({
          sessionId: payload.sessionId,
          direction: 'inbound',
          transferId: payload.transferId,
          items: payload.items,
        })

        if (options.defaultSaveDirectory) {
          const accepted = transferManager.acceptTransfer(payload.sessionId, payload.transferId, options.defaultSaveDirectory)
          socket.send(
            JSON.stringify(
              createTransferAcceptMessage({
                sessionId: accepted.sessionId,
                transferId: accepted.transferId,
              }),
            ),
          )
        }
        return
      }

      if (message.type !== 'connect_request' || !message.payload) {
        return
      }

      const payload = message.payload as ConnectRequestPayload
      if (payload.pairToken !== options.pairToken) {
        socket.send(JSON.stringify(createConnectRejectedMessage({ reason: 'invalid_pair_token' })))
        return
      }

      connectionManager.addPending({
        deviceId: payload.deviceId,
        deviceName: payload.deviceName,
        deviceType: payload.deviceType,
        socketId,
      })
    })

    socket.on('close', () => {
      connectionManager.removePendingBySocketId(socketId)
      connectionManager.disconnectBySocketId(socketId)
      sockets.delete(socketId)
    })
  })

  return {
    async listen(port: number) {
      hostServer.server.listen(port, '0.0.0.0')
      await once(hostServer.server, 'listening')
      currentPort = (hostServer.server.address() as AddressInfo).port
      return currentPort
    },
    getSnapshot() {
      return {
        pending: connectionManager.listPending(),
        sessions: connectionManager.listSessions(),
      }
    },
    getHostInfo() {
      return buildHostInfo()
    },
    approve(requestId: string) {
      const session = connectionManager.approve(requestId)
      const socket = sockets.get(session.socketId)
      socket?.send(
        JSON.stringify(
          createConnectApprovedMessage({
            sessionId: session.sessionId,
            remoteDeviceId: session.remoteDeviceId,
          }),
        ),
      )
      return session
    },
    disconnectSession(sessionId: string) {
      const session = connectionManager.disconnectSession(sessionId)
      const socket = sockets.get(session.socketId)
      socket?.close()
      return session
    },
    listMessages(sessionId: string) {
      return messages.get(sessionId) ?? []
    },
    sendTextMessage(sessionId: string, text: string) {
      const session = connectionManager.findSessionById(sessionId)
      if (!session) {
        throw new Error('session not found')
      }

      const payload: TextMessagePayload = {
        sessionId,
        messageId: randomUUID(),
        text,
        senderId: options.hostId,
        sentAt: new Date().toISOString(),
      }

      const currentMessages = messages.get(sessionId) ?? []
      currentMessages.push(payload)
      messages.set(sessionId, currentMessages)

      sockets.get(session.socketId)?.send(JSON.stringify(createTextMessage(payload)))
      return payload
    },
    createTransferOffer(input: { sessionId: string; direction: 'outbound' | 'inbound'; items: TransferItem[] }) {
      return transferManager.createOffer(input)
    },
    approveTransfer(sessionId: string, transferId: string, targetDirectory: string) {
      const transfer = transferManager.acceptTransfer(sessionId, transferId, targetDirectory)
      getSocketBySessionId(sessionId)?.send(
        JSON.stringify(
          createTransferAcceptMessage({
            sessionId,
            transferId,
          }),
        ),
      )
      return transfer
    },
    rejectTransfer(sessionId: string, transferId: string, reason = 'receiver_declined') {
      const transfer = transferManager.rejectTransfer(sessionId, transferId, reason)
      getSocketBySessionId(sessionId)?.send(
        JSON.stringify(
          createTransferRejectMessage({
            sessionId,
            transferId,
            reason: 'receiver_declined',
          }),
        ),
      )
      return transfer
    },
    acceptTransfer(sessionId: string, transferId: string, targetDirectory: string) {
      return transferManager.acceptTransfer(sessionId, transferId, targetDirectory)
    },
    getTransfer(sessionId: string, transferId: string) {
      return transferManager.getTransfer(sessionId, transferId)
    },
    listTransfers(sessionId: string) {
      return transferManager.listBySession(sessionId)
    },
    failTransferItem(sessionId: string, transferId: string, relativePath: string, error: string) {
      return transferManager.markItemFailed(sessionId, transferId, relativePath, error)
    },
    retryFailedTransferItems(sessionId: string, transferId: string) {
      return transferManager.retryFailedItems(sessionId, transferId)
    },
    async close() {
      for (const socket of sockets.values()) {
        socket.close()
      }

      hostServer.websocket.close()
      await new Promise<void>((resolve, reject) => {
        hostServer.server.close((error) => {
          if (error) {
            reject(error)
            return
          }

          resolve()
        })
      })
    },
  }
}
