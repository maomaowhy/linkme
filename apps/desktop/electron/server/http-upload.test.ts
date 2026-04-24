import { describe, expect, it } from 'vitest'
import { TransferManager } from './transfer-manager'

describe('TransferManager acceptance', () => {
  it('marks an offered transfer as accepted', () => {
    const manager = new TransferManager()
    const transfer = manager.createOffer({
      sessionId: 'session-1',
      direction: 'inbound',
      items: [{ relativePath: 'folder/a.txt', size: 30, kind: 'file' }],
    })

    const accepted = manager.acceptTransfer('session-1', transfer.transferId, '/tmp/save-dir')
    expect(accepted.status).toBe('accepted')
    expect(accepted.targetDirectory).toBe('/tmp/save-dir')
  })
})
