import { describe, expect, it } from 'vitest'
import { parseQrPayload, stringifyQrPayload } from './qrcode'

describe('qr payload', () => {
  it('round-trips a valid host payload', () => {
    const encoded = stringifyQrPayload({
      version: 1,
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '192.168.1.8',
      port: 19090,
      pairToken: 'token-1',
      expiresAt: '2026-04-24T12:00:00.000Z',
    })

    const parsed = parseQrPayload(encoded)
    expect(parsed.hostIp).toBe('192.168.1.8')
    expect(parsed.port).toBe(19090)
  })
})
