import { describe, expect, it } from 'vitest'
import { ConnectionManager } from './connection-manager'

describe('ConnectionManager', () => {
  it('stores pending connection requests before approval', () => {
    const manager = new ConnectionManager()

    const requestId = manager.addPending({
      deviceId: 'mobile-1',
      deviceName: 'Pixel',
      deviceType: 'mobile',
      socketId: 'socket-1',
    })

    expect(manager.listPending()).toHaveLength(1)
    expect(manager.listPending()[0]?.requestId).toBe(requestId)
  })

  it('moves a pending request to active session when approved', () => {
    const manager = new ConnectionManager()
    const requestId = manager.addPending({
      deviceId: 'mobile-1',
      deviceName: 'Pixel',
      deviceType: 'mobile',
      socketId: 'socket-1',
    })

    const session = manager.approve(requestId)

    expect(session.status).toBe('connected')
    expect(manager.listPending()).toHaveLength(0)
    expect(manager.listSessions()).toHaveLength(1)
  })
})
