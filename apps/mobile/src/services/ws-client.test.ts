import { describe, expect, it } from 'vitest'
import { createSessionState } from './ws-client'

describe('createSessionState', () => {
  it('starts in idle state and enters pending after connect request', () => {
    const session = createSessionState()

    expect(session.status.value).toBe('idle')
    session.markPendingApproval()
    expect(session.status.value).toBe('pending')
  })
})
