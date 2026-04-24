import { describe, expect, it } from 'vitest'
import {
  createConnectApprovedMessage,
  createConnectRequestMessage,
  createTransferAcceptMessage,
  createTransferOfferMessage,
  createTransferRejectMessage,
} from './messages'

describe('protocol messages', () => {
  it('creates a connect request with device metadata', () => {
    const message = createConnectRequestMessage({
      deviceId: 'mobile-1',
      deviceName: 'Pixel',
      deviceType: 'mobile',
      pairToken: 'token-1',
    })

    expect(message.type).toBe('connect_request')
    expect(message.payload.deviceId).toBe('mobile-1')
    expect(message.payload.deviceType).toBe('mobile')
    expect(message.payload.pairToken).toBe('token-1')
  })

  it('creates an approval message with session id', () => {
    const message = createConnectApprovedMessage({
      sessionId: 'session-1',
      remoteDeviceId: 'mobile-1',
    })

    expect(message.type).toBe('connect_approved')
    expect(message.payload.sessionId).toBe('session-1')
  })

  it('creates transfer offer, accept, and reject messages', () => {
    const offer = createTransferOfferMessage({
      sessionId: 'session-1',
      transferId: 'transfer-1',
      itemCount: 2,
      totalBytes: 30,
      items: [
        { relativePath: 'docs/a.txt', size: 10, kind: 'file' },
        { relativePath: 'docs/b.txt', size: 20, kind: 'file' },
      ],
    })
    const accept = createTransferAcceptMessage({
      sessionId: 'session-1',
      transferId: 'transfer-1',
    })
    const reject = createTransferRejectMessage({
      sessionId: 'session-1',
      transferId: 'transfer-1',
      reason: 'receiver_declined',
    })

    expect(offer.type).toBe('transfer_offer')
    expect(offer.payload.itemCount).toBe(2)
    expect(accept.type).toBe('transfer_accept')
    expect(accept.payload.transferId).toBe('transfer-1')
    expect(reject.type).toBe('transfer_reject')
    expect(reject.payload.reason).toBe('receiver_declined')
  })
})
