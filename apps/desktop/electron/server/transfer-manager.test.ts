import { describe, expect, it } from 'vitest'
import { TransferManager } from './transfer-manager'

describe('TransferManager', () => {
  it('creates an offered transfer in waiting state', () => {
    const manager = new TransferManager()

    const transfer = manager.createOffer({
      sessionId: 'session-1',
      direction: 'outbound',
      items: [{ relativePath: 'docs/a.txt', size: 12, kind: 'file' }],
    })

    expect(transfer.status).toBe('offered')
    expect(manager.listBySession('session-1')).toHaveLength(1)
    expect(transfer.items[0]?.status).toBe('waiting')
  })

  it('tracks per-file results and completes with errors when one item fails', () => {
    const manager = new TransferManager()

    const transfer = manager.createOffer({
      sessionId: 'session-1',
      direction: 'inbound',
      items: [
        { relativePath: 'docs/a.txt', size: 10, kind: 'file' },
        { relativePath: 'docs/b.txt', size: 20, kind: 'file' },
        { relativePath: 'docs/c.txt', size: 30, kind: 'file' },
      ],
    })

    manager.acceptTransfer('session-1', transfer.transferId, '/tmp/save-dir')

    manager.markItemTransferring('session-1', transfer.transferId, 'docs/a.txt')
    manager.markItemSucceeded('session-1', transfer.transferId, 'docs/a.txt', '/tmp/save-dir/docs/a.txt', 10)

    manager.markItemTransferring('session-1', transfer.transferId, 'docs/b.txt')
    manager.markItemFailed('session-1', transfer.transferId, 'docs/b.txt', 'disk full')

    manager.markItemTransferring('session-1', transfer.transferId, 'docs/c.txt')
    const result = manager.markItemSucceeded(
      'session-1',
      transfer.transferId,
      'docs/c.txt',
      '/tmp/save-dir/docs/c.txt',
      30,
    )

    expect(result.status).toBe('completed_with_errors')
    expect(result.items).toMatchObject([
      { relativePath: 'docs/a.txt', status: 'success', savedPath: '/tmp/save-dir/docs/a.txt' },
      { relativePath: 'docs/b.txt', status: 'failed', error: 'disk full' },
      { relativePath: 'docs/c.txt', status: 'success', savedPath: '/tmp/save-dir/docs/c.txt' },
    ])
    expect(result.summary).toMatchObject({
      totalCount: 3,
      successCount: 2,
      failedCount: 1,
    })
  })

  it('retries only failed items without resetting successful ones', () => {
    const manager = new TransferManager()

    const transfer = manager.createOffer({
      sessionId: 'session-1',
      direction: 'inbound',
      items: [
        { relativePath: 'docs/a.txt', size: 10, kind: 'file' },
        { relativePath: 'docs/b.txt', size: 20, kind: 'file' },
      ],
    })

    manager.acceptTransfer('session-1', transfer.transferId, '/tmp/save-dir')
    manager.markItemTransferring('session-1', transfer.transferId, 'docs/a.txt')
    manager.markItemSucceeded('session-1', transfer.transferId, 'docs/a.txt', '/tmp/save-dir/docs/a.txt', 10)
    manager.markItemTransferring('session-1', transfer.transferId, 'docs/b.txt')
    manager.markItemFailed('session-1', transfer.transferId, 'docs/b.txt', 'timeout')

    const retried = manager.retryFailedItems('session-1', transfer.transferId)

    expect(retried.status).toBe('accepted')
    expect(retried.items).toMatchObject([
      { relativePath: 'docs/a.txt', status: 'success', attempts: 1 },
      { relativePath: 'docs/b.txt', status: 'waiting', attempts: 1 },
    ])
  })

  it('marks an offered transfer as rejected without mutating file results', () => {
    const manager = new TransferManager()

    const transfer = manager.createOffer({
      sessionId: 'session-1',
      direction: 'inbound',
      items: [{ relativePath: 'docs/a.txt', size: 10, kind: 'file' }],
    })

    const rejected = manager.rejectTransfer('session-1', transfer.transferId, 'receiver_declined')

    expect(rejected.status).toBe('rejected')
    expect(rejected.rejectionReason).toBe('receiver_declined')
    expect(rejected.items[0]?.status).toBe('waiting')
  })
})
