import { BrowserWindow, app, dialog, ipcMain } from 'electron'
import { randomUUID } from 'node:crypto'
import { networkInterfaces } from 'node:os'
import { join } from 'node:path'
import { createDesktopHostService } from './server/host-service'

const resolveHostIp = () => {
  const networks = networkInterfaces()
  for (const entries of Object.values(networks)) {
    for (const entry of entries ?? []) {
      if (entry.family === 'IPv4' && !entry.internal) {
        return entry.address
      }
    }
  }

  return '127.0.0.1'
}

const hostService = createDesktopHostService({
  hostId: randomUUID(),
  hostName: 'Link Me Desktop',
  hostIp: resolveHostIp(),
  pairToken: randomUUID(),
  defaultSaveDirectory: undefined,
})

const createWindow = async () => {
  const window = new BrowserWindow({
    width: 1280,
    height: 840,
    webPreferences: {
      preload: join(__dirname, 'preload.cjs'),
    },
  })

  if (process.env.VITE_DEV_SERVER_URL) {
    await window.loadURL(process.env.VITE_DEV_SERVER_URL)
    return
  }

  await window.loadFile(join(__dirname, '../dist/index.html'))
}

app.whenReady().then(async () => {
  await hostService.listen(19090)

  ipcMain.handle('host:get-info', () => hostService.getHostInfo())
  ipcMain.handle('host:get-snapshot', () => hostService.getSnapshot())
  ipcMain.handle('host:approve', (_event, requestId: string) => hostService.approve(requestId))
  ipcMain.handle('host:disconnect', (_event, sessionId: string) => hostService.disconnectSession(sessionId))
  ipcMain.handle('host:list-messages', (_event, sessionId: string) => hostService.listMessages(sessionId))
  ipcMain.handle('host:send-text', (_event, sessionId: string, text: string) =>
    hostService.sendTextMessage(sessionId, text),
  )
  ipcMain.handle('host:list-transfers', (_event, sessionId: string) => hostService.listTransfers(sessionId))
  ipcMain.handle('host:retry-failed-items', (_event, sessionId: string, transferId: string) =>
    hostService.retryFailedTransferItems(sessionId, transferId),
  )
  ipcMain.handle('host:accept-transfer', async (_event, sessionId: string, transferId: string) => {
    const selected = await dialog.showOpenDialog({
      properties: ['openDirectory', 'createDirectory'],
      title: '选择本次接收保存位置',
      buttonLabel: '保存到这里',
    })

    if (selected.canceled || selected.filePaths.length === 0) {
      return null
    }

    return hostService.approveTransfer(sessionId, transferId, selected.filePaths[0])
  })
  ipcMain.handle('host:reject-transfer', (_event, sessionId: string, transferId: string) =>
    hostService.rejectTransfer(sessionId, transferId),
  )

  await createWindow()
})

app.on('before-quit', async () => {
  await hostService.close()
})
