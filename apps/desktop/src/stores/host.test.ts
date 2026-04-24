import { describe, expect, it } from 'vitest'
import { createHostStore } from './host'

describe('createHostStore', () => {
  it('records pending devices and active sessions separately', () => {
    const store = createHostStore()

    store.setPending([{ requestId: 'request-1', deviceName: 'Pixel' }])
    store.setSessions([{ sessionId: 'session-1', remoteDeviceName: 'Pixel', status: 'connected' }])

    expect(store.pending.value).toHaveLength(1)
    expect(store.sessions.value).toHaveLength(1)
  })

  it('selects the first session by default and stores transfer batches by session', () => {
    const store = createHostStore()

    store.setSessions([
      { sessionId: 'session-1', remoteDeviceName: 'Pixel', status: 'connected' },
      { sessionId: 'session-2', remoteDeviceName: 'Xiaomi', status: 'connected' },
    ])
    store.setTransfers('session-1', [
      {
        transferId: 'transfer-1',
        status: 'completed_with_errors',
        items: [
          { relativePath: 'docs/a.txt', status: 'success', attempts: 1 },
          { relativePath: 'docs/b.txt', status: 'failed', attempts: 1, error: 'timeout' },
        ],
        summary: { totalCount: 2, successCount: 1, failedCount: 1 },
      },
    ])

    expect(store.selectedSessionId.value).toBe('session-1')
    expect(store.currentTransfers.value[0]?.transferId).toBe('transfer-1')
    expect(store.currentTransfers.value[0]?.summary.failedCount).toBe(1)
  })

  it('keeps selected session when refreshing sessions and allows switching sessions', () => {
    const store = createHostStore()

    store.setSessions([
      { sessionId: 'session-1', remoteDeviceName: 'Pixel', status: 'connected' },
      { sessionId: 'session-2', remoteDeviceName: 'Xiaomi', status: 'connected' },
    ])
    store.selectSession('session-2')
    store.setTransfers('session-2', [
      {
        transferId: 'transfer-2',
        status: 'completed',
        items: [{ relativePath: 'docs/c.txt', status: 'success', attempts: 1 }],
        summary: { totalCount: 1, successCount: 1, failedCount: 0 },
      },
    ])

    store.setSessions([
      { sessionId: 'session-1', remoteDeviceName: 'Pixel', status: 'connected' },
      { sessionId: 'session-2', remoteDeviceName: 'Xiaomi', status: 'connected' },
    ])

    expect(store.selectedSessionId.value).toBe('session-2')
    expect(store.currentTransfers.value[0]?.transferId).toBe('transfer-2')
  })
})
