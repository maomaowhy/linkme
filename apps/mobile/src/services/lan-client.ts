import { ref } from 'vue'
import {
  createConnectRequestMessage,
  createTransferOfferMessage,
  parseQrPayload,
  type ConnectRequestPayload,
  type TransferManifest,
} from '@link-me/shared'

interface LanSocket {
  send(data: string): void
  close(): void
  onOpen(listener: () => void): void
  onMessage(listener: (payload: string) => void): void
  onClose(listener: () => void): void
  onError(listener: (error: Error) => void): void
}

interface CreateLanClientOptions {
  socketFactory: (url: string) => LanSocket
}

type RejectionReason = 'invalid_pair_token' | 'rejected_by_host' | ''
type TransferRejectionReason = 'receiver_declined'

export const createLanClient = ({ socketFactory }: CreateLanClientOptions) => {
  const status = ref<'idle' | 'pending' | 'connected' | 'disconnected'>('idle')
  const sessionId = ref('')
  const lastError = ref<RejectionReason>('')
  const connectionInfo = ref<{ hostIp: string; port: number } | null>(null)
  const lastAcceptedTransfer = ref<{ sessionId: string; transferId: string } | null>(null)
  const lastRejectedTransfer = ref<{
    sessionId: string
    transferId: string
    reason: TransferRejectionReason
  } | null>(null)
  let socket: LanSocket | undefined

  return {
    status,
    sessionId,
    lastError,
    connectionInfo,
    lastAcceptedTransfer,
    lastRejectedTransfer,
    connectFromQrPayload(qrPayload: string, device: Omit<ConnectRequestPayload, 'pairToken'>) {
      const payload = parseQrPayload(qrPayload)
      connectionInfo.value = {
        hostIp: payload.hostIp,
        port: payload.port,
      }
      socket = socketFactory(`ws://${payload.hostIp}:${payload.port}`)

      socket.onOpen(() => {
        status.value = 'pending'
        socket?.send(
          JSON.stringify(
            createConnectRequestMessage({
              ...device,
              pairToken: payload.pairToken,
            }),
          ),
        )
      })

      socket.onMessage((raw) => {
        const message = JSON.parse(raw) as {
          type: 'connect_approved' | 'connect_rejected' | 'transfer_accept' | 'transfer_reject'
          payload: {
            sessionId?: string
            reason?: RejectionReason | TransferRejectionReason
            transferId?: string
          }
        }

        if (message.type === 'connect_approved' && message.payload.sessionId) {
          status.value = 'connected'
          sessionId.value = message.payload.sessionId
          lastError.value = ''
          return
        }

        if (message.type === 'connect_rejected' && message.payload.reason) {
          status.value = 'disconnected'
          lastError.value = message.payload.reason as RejectionReason
          return
        }

        if (message.type === 'transfer_accept' && message.payload.sessionId && message.payload.transferId) {
          lastAcceptedTransfer.value = {
            sessionId: message.payload.sessionId,
            transferId: message.payload.transferId,
          }
          lastRejectedTransfer.value = null
          return
        }

        if (message.type === 'transfer_reject' && message.payload.sessionId && message.payload.transferId) {
          lastRejectedTransfer.value = {
            sessionId: message.payload.sessionId,
            transferId: message.payload.transferId,
            reason: (message.payload.reason as TransferRejectionReason) ?? 'receiver_declined',
          }
        }
      })

      socket.onClose(() => {
        if (status.value !== 'idle') {
          status.value = 'disconnected'
        }
      })

      socket.onError(() => {
        status.value = 'disconnected'
      })
    },
    sendTransferOffer(manifest: TransferManifest) {
      socket?.send(
        JSON.stringify(
          createTransferOfferMessage({
            sessionId: manifest.sessionId,
            transferId: manifest.transferId,
            itemCount: manifest.itemCount,
            totalBytes: manifest.totalBytes,
            items: manifest.items,
          }),
        ),
      )
    },
    disconnect() {
      socket?.close()
    },
  }
}
