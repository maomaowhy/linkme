import { contextBridge, ipcRenderer } from 'electron'

contextBridge.exposeInMainWorld('linkMe', {
  ping: () => 'pong',
  host: {
    getInfo: () => ipcRenderer.invoke('host:get-info'),
    getSnapshot: () => ipcRenderer.invoke('host:get-snapshot'),
    approve: (requestId: string) => ipcRenderer.invoke('host:approve', requestId),
    disconnect: (sessionId: string) => ipcRenderer.invoke('host:disconnect', sessionId),
    listMessages: (sessionId: string) => ipcRenderer.invoke('host:list-messages', sessionId),
    sendText: (sessionId: string, text: string) => ipcRenderer.invoke('host:send-text', sessionId, text),
    listTransfers: (sessionId: string) => ipcRenderer.invoke('host:list-transfers', sessionId),
    retryFailedItems: (sessionId: string, transferId: string) =>
      ipcRenderer.invoke('host:retry-failed-items', sessionId, transferId),
    acceptTransfer: (sessionId: string, transferId: string) =>
      ipcRenderer.invoke('host:accept-transfer', sessionId, transferId),
    rejectTransfer: (sessionId: string, transferId: string) =>
      ipcRenderer.invoke('host:reject-transfer', sessionId, transferId),
  },
})
