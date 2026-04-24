import { afterEach, describe, expect, it } from 'vitest'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import WebSocket from 'ws'
import { parseQrPayload } from '@link-me/shared'
import { createDesktopHostService } from './host-service'

const openClient = async (url: string) => {
  const client = new WebSocket(url)

  await new Promise<void>((resolve, reject) => {
    client.once('open', () => resolve())
    client.once('error', (error) => reject(error))
  })

  return client
}

const readMessage = (client: WebSocket) =>
  new Promise<Record<string, any>>((resolve, reject) => {
    client.once('message', (data) => {
      try {
        resolve(JSON.parse(data.toString()))
      } catch (error) {
        reject(error)
      }
    })
    client.once('error', (error) => reject(error))
  })

describe('createDesktopHostService', () => {
  const activeServices: Array<{ close: () => Promise<void> }> = []

  afterEach(async () => {
    while (activeServices.length > 0) {
      const service = activeServices.pop()
      if (service) {
        await service.close()
      }
    }
  })

  it('stores a pending request after a valid connect_request', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'token-1',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))

    expect(service.getSnapshot().pending).toHaveLength(1)
    client.close()
  })

  it('rejects a connect_request when pair token is invalid', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)
    const rejectedMessage = readMessage(client)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'bad-token',
        },
      }),
    )

    await expect(rejectedMessage).resolves.toMatchObject({
      type: 'connect_rejected',
      payload: {
        reason: 'invalid_pair_token',
      },
    })

    expect(service.getSnapshot().pending).toHaveLength(0)
    client.close()
  })

  it('approves a pending request and emits connect_approved to the client', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'token-1',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    const requestId = service.getSnapshot().pending[0]?.requestId
    expect(requestId).toBeTruthy()

    const approvedMessage = readMessage(client)
    const session = service.approve(requestId!)

    await expect(approvedMessage).resolves.toMatchObject({
      type: 'connect_approved',
      payload: {
        sessionId: session.sessionId,
        remoteDeviceId: 'mobile-1',
      },
    })

    expect(service.getSnapshot().sessions).toHaveLength(1)
    client.close()
  })

  it('disconnects an approved session and updates the snapshot', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'token-1',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    const requestId = service.getSnapshot().pending[0]?.requestId
    const closed = new Promise<void>((resolve) => {
      client.once('close', () => resolve())
    })

    const session = service.approve(requestId!)
    await readMessage(client)

    service.disconnectSession(session.sessionId)

    await closed
    expect(service.getSnapshot().sessions[0]?.status).toBe('disconnected')
  })

  it('returns host info with a parseable QR payload', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const response = await fetch(`http://127.0.0.1:${port}/api/host-info`)
    const body = (await response.json()) as { qrPayload: string; port: number; hostIp: string }
    const payload = parseQrPayload(body.qrPayload)

    expect(response.ok).toBe(true)
    expect(body.port).toBe(port)
    expect(payload.hostIp).toBe('127.0.0.1')
    expect(payload.port).toBe(port)
  })

  it('stores inbound text messages after a session is approved', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'token-1',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    const session = service.approve(service.getSnapshot().pending[0]!.requestId)
    await readMessage(client)

    client.send(
      JSON.stringify({
        type: 'text_message',
        payload: {
          sessionId: session.sessionId,
          messageId: 'message-1',
          text: 'hello from mobile',
          senderId: 'mobile-1',
          sentAt: '2026-04-24T12:00:00.000Z',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    expect(service.listMessages(session.sessionId)).toMatchObject([
      {
        text: 'hello from mobile',
        senderId: 'mobile-1',
      },
    ])
    client.close()
  })

  it('sends outbound text messages to an approved client', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'token-1',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    const session = service.approve(service.getSnapshot().pending[0]!.requestId)
    await readMessage(client)

    const nextMessage = readMessage(client)
    const outbound = service.sendTextMessage(session.sessionId, 'hello from desktop')

    await expect(nextMessage).resolves.toMatchObject({
      type: 'text_message',
      payload: {
        sessionId: session.sessionId,
        text: 'hello from desktop',
      },
    })

    expect(outbound.text).toBe('hello from desktop')
    client.close()
  })

  it('keeps incoming transfer in offered state until desktop selects a save directory', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'token-1',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    const session = service.approve(service.getSnapshot().pending[0]!.requestId)
    await readMessage(client)

    client.send(
      JSON.stringify({
        type: 'transfer_offer',
        payload: {
          sessionId: session.sessionId,
          transferId: 'transfer-offer-1',
          itemCount: 1,
          totalBytes: 11,
          items: [{ relativePath: 'docs/hello.txt', size: 11, kind: 'file' }],
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    expect(service.getTransfer(session.sessionId, 'transfer-offer-1')).toMatchObject({
      status: 'offered',
      targetDirectory: undefined,
    })
    client.close()
  })

  it('creates and auto-accepts a transfer after receiving transfer_offer when a default directory exists', async () => {
    const saveDir = await mkdtemp(join(tmpdir(), 'link-me-offer-'))
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
      defaultSaveDirectory: saveDir,
    })
    activeServices.push(service)

    try {
      const port = await service.listen(0)
      const client = await openClient(`ws://127.0.0.1:${port}`)

      client.send(
        JSON.stringify({
          type: 'connect_request',
          payload: {
            deviceId: 'mobile-1',
            deviceName: 'Pixel',
            deviceType: 'mobile',
            pairToken: 'token-1',
          },
        }),
      )

      await new Promise((resolve) => setTimeout(resolve, 30))
      const session = service.approve(service.getSnapshot().pending[0]!.requestId)
      await readMessage(client)

      const acceptedMessage = readMessage(client)
      client.send(
        JSON.stringify({
          type: 'transfer_offer',
          payload: {
            sessionId: session.sessionId,
            transferId: 'transfer-offer-1',
            itemCount: 1,
            totalBytes: 11,
            items: [{ relativePath: 'docs/hello.txt', size: 11, kind: 'file' }],
          },
        }),
      )

      await expect(acceptedMessage).resolves.toMatchObject({
        type: 'transfer_accept',
        payload: {
          sessionId: session.sessionId,
          transferId: 'transfer-offer-1',
        },
      })
      expect(service.getTransfer(session.sessionId, 'transfer-offer-1')).toMatchObject({
        status: 'accepted',
        targetDirectory: saveDir,
      })
      client.close()
    } finally {
      await rm(saveDir, { recursive: true, force: true })
    }
  })

  it('approves an offered transfer and notifies the sender', async () => {
    const saveDir = await mkdtemp(join(tmpdir(), 'link-me-manual-approve-'))
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    try {
      const port = await service.listen(0)
      const client = await openClient(`ws://127.0.0.1:${port}`)

      client.send(
        JSON.stringify({
          type: 'connect_request',
          payload: {
            deviceId: 'mobile-1',
            deviceName: 'Pixel',
            deviceType: 'mobile',
            pairToken: 'token-1',
          },
        }),
      )

      await new Promise((resolve) => setTimeout(resolve, 30))
      const session = service.approve(service.getSnapshot().pending[0]!.requestId)
      await readMessage(client)

      client.send(
        JSON.stringify({
          type: 'transfer_offer',
          payload: {
            sessionId: session.sessionId,
            transferId: 'transfer-offer-1',
            itemCount: 1,
            totalBytes: 11,
            items: [{ relativePath: 'docs/hello.txt', size: 11, kind: 'file' }],
          },
        }),
      )

      await new Promise((resolve) => setTimeout(resolve, 30))
      const acceptedMessage = readMessage(client)
      service.approveTransfer(session.sessionId, 'transfer-offer-1', saveDir)

      await expect(acceptedMessage).resolves.toMatchObject({
        type: 'transfer_accept',
        payload: {
          sessionId: session.sessionId,
          transferId: 'transfer-offer-1',
        },
      })
      expect(service.getTransfer(session.sessionId, 'transfer-offer-1')).toMatchObject({
        status: 'accepted',
        targetDirectory: saveDir,
      })
      client.close()
    } finally {
      await rm(saveDir, { recursive: true, force: true })
    }
  })

  it('rejects an offered transfer and notifies the sender', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const client = await openClient(`ws://127.0.0.1:${port}`)

    client.send(
      JSON.stringify({
        type: 'connect_request',
        payload: {
          deviceId: 'mobile-1',
          deviceName: 'Pixel',
          deviceType: 'mobile',
          pairToken: 'token-1',
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    const session = service.approve(service.getSnapshot().pending[0]!.requestId)
    await readMessage(client)

    client.send(
      JSON.stringify({
        type: 'transfer_offer',
        payload: {
          sessionId: session.sessionId,
          transferId: 'transfer-offer-1',
          itemCount: 1,
          totalBytes: 11,
          items: [{ relativePath: 'docs/hello.txt', size: 11, kind: 'file' }],
        },
      }),
    )

    await new Promise((resolve) => setTimeout(resolve, 30))
    const rejectedMessage = readMessage(client)
    service.rejectTransfer(session.sessionId, 'transfer-offer-1')

    await expect(rejectedMessage).resolves.toMatchObject({
      type: 'transfer_reject',
      payload: {
        sessionId: session.sessionId,
        transferId: 'transfer-offer-1',
        reason: 'receiver_declined',
      },
    })
    expect(service.getTransfer(session.sessionId, 'transfer-offer-1')).toMatchObject({
      status: 'rejected',
      rejectionReason: 'receiver_declined',
    })
    client.close()
  })


  it('responds to upload preflight with cors headers for h5 clients', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const port = await service.listen(0)
    const response = await fetch(`http://127.0.0.1:${port}/api/transfers/session-1/transfer-1/upload`, {
      method: 'OPTIONS',
      headers: {
        origin: 'http://127.0.0.1:5174',
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'content-type,x-relative-path',
      },
    })

    expect(response.status).toBe(204)
    expect(response.headers.get('access-control-allow-origin')).toBe('*')
    expect(response.headers.get('access-control-allow-methods')).toContain('POST')
    expect(response.headers.get('access-control-allow-headers')).toContain('x-relative-path')
  })

  it('writes uploaded files into the accepted transfer target directory', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const saveDir = await mkdtemp(join(tmpdir(), 'link-me-upload-'))

    try {
      const port = await service.listen(0)
      const client = await openClient(`ws://127.0.0.1:${port}`)

      client.send(
        JSON.stringify({
          type: 'connect_request',
          payload: {
            deviceId: 'mobile-1',
            deviceName: 'Pixel',
            deviceType: 'mobile',
            pairToken: 'token-1',
          },
        }),
      )

      await new Promise((resolve) => setTimeout(resolve, 30))
      const session = service.approve(service.getSnapshot().pending[0]!.requestId)
      await readMessage(client)

      const transfer = service.createTransferOffer({
        sessionId: session.sessionId,
        direction: 'inbound',
        items: [{ relativePath: 'docs/hello.txt', size: 11, kind: 'file' }],
      })

      service.acceptTransfer(session.sessionId, transfer.transferId, saveDir)

      const response = await fetch(`http://127.0.0.1:${port}/api/transfers/${session.sessionId}/${transfer.transferId}/upload`, {
        method: 'POST',
        headers: {
          'content-type': 'application/octet-stream',
          'x-relative-path': 'docs/hello.txt',
        },
        body: Buffer.from('hello world'),
      })

      expect(response.ok).toBe(true)
      await expect(readFile(join(saveDir, 'docs/hello.txt'), 'utf8')).resolves.toBe('hello world')
      expect(service.getTransfer(session.sessionId, transfer.transferId)).toMatchObject({
        status: 'completed',
        items: [{ relativePath: 'docs/hello.txt', status: 'success' }],
        summary: { successCount: 1, failedCount: 0, totalCount: 1 },
      })
      client.close()
    } finally {
      await rm(saveDir, { recursive: true, force: true })
    }
  })

  it('lists transfers for a session and retries only failed items', async () => {
    const service = createDesktopHostService({
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '127.0.0.1',
      pairToken: 'token-1',
    })
    activeServices.push(service)

    const saveDir = await mkdtemp(join(tmpdir(), 'link-me-retry-'))

    try {
      const port = await service.listen(0)
      const client = await openClient(`ws://127.0.0.1:${port}`)

      client.send(
        JSON.stringify({
          type: 'connect_request',
          payload: {
            deviceId: 'mobile-1',
            deviceName: 'Pixel',
            deviceType: 'mobile',
            pairToken: 'token-1',
          },
        }),
      )

      await new Promise((resolve) => setTimeout(resolve, 30))
      const session = service.approve(service.getSnapshot().pending[0]!.requestId)
      await readMessage(client)

      const transfer = service.createTransferOffer({
        sessionId: session.sessionId,
        direction: 'inbound',
        items: [
          { relativePath: 'docs/ok.txt', size: 2, kind: 'file' },
          { relativePath: 'docs/bad.txt', size: 3, kind: 'file' },
        ],
      })

      service.acceptTransfer(session.sessionId, transfer.transferId, saveDir)

      await fetch(`http://127.0.0.1:${port}/api/transfers/${session.sessionId}/${transfer.transferId}/upload`, {
        method: 'POST',
        headers: {
          'content-type': 'application/octet-stream',
          'x-relative-path': 'docs/ok.txt',
        },
        body: Buffer.from('ok'),
      })

      service.failTransferItem(session.sessionId, transfer.transferId, 'docs/bad.txt', 'timeout')

      expect(service.listTransfers(session.sessionId)).toHaveLength(1)
      const retried = service.retryFailedTransferItems(session.sessionId, transfer.transferId)
      expect(retried.items).toMatchObject([
        { relativePath: 'docs/ok.txt', status: 'success', attempts: 1 },
        { relativePath: 'docs/bad.txt', status: 'waiting', attempts: 1 },
      ])
      client.close()
    } finally {
      await rm(saveDir, { recursive: true, force: true })
    }
  })
})
