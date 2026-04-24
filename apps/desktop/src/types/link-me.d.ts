export {}

type HostTransferItem = {
  relativePath: string
  status: string
  attempts: number
  error?: string
  savedPath?: string
}

type HostTransferBatch = {
  transferId: string
  status: string
  items: HostTransferItem[]
  targetDirectory?: string
  rejectionReason?: string
  summary: {
    totalCount: number
    successCount: number
    failedCount: number
  }
}

declare global {
  interface Window {
    linkMe?: {
      ping: () => string
      host: {
        getInfo: () => Promise<{ hostId: string; hostName: string; hostIp: string; port: number; qrPayload: string }>
        getSnapshot: () => Promise<{
          pending: Array<{ requestId: string; deviceId: string; deviceName: string; deviceType: string; socketId: string }>
          sessions: Array<{
            sessionId: string
            remoteDeviceId: string
            remoteDeviceName: string
            remoteDeviceType: string
            socketId: string
            status: string
          }>
        }>
        approve: (requestId: string) => Promise<unknown>
        disconnect: (sessionId: string) => Promise<unknown>
        listMessages: (sessionId: string) => Promise<unknown>
        sendText: (sessionId: string, text: string) => Promise<unknown>
        listTransfers: (sessionId: string) => Promise<HostTransferBatch[]>
        retryFailedItems: (sessionId: string, transferId: string) => Promise<HostTransferBatch>
        acceptTransfer: (sessionId: string, transferId: string) => Promise<HostTransferBatch | null>
        rejectTransfer: (sessionId: string, transferId: string) => Promise<HostTransferBatch>
      }
    }
  }
}
