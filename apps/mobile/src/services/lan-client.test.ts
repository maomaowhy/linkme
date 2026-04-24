import { describe, expect, it } from 'vitest'
import { createTransferManifest } from '@link-me/shared'
import { createLanClient } from './lan-client'

const createMockSocket = () => {
  const listeners: Record<string, Array<(payload?: any) => void>> = {
    open: [],
    message: [],
    close: [],
    error: [],
  }

  return {
    sent: [] as string[],
    send(data: string) {
      this.sent.push(data)
    },
    close() {
      listeners.close.forEach((listener) => listener())
    },
    onOpen(listener: () => void) {
      listeners.open.push(listener)
    },
    onMessage(listener: (payload: string) => void) {
      listeners.message.push(listener)
    },
    onClose(listener: () => void) {
      listeners.close.push(listener)
    },
    onError(listener: (error: Error) => void) {
      listeners.error.push(listener)
    },
    emitOpen() {
      listeners.open.forEach((listener) => listener())
    },
    emitMessage(payload: unknown) {
      listeners.message.forEach((listener) => listener(JSON.stringify(payload)))
    },
  }
}

describe('createLanClient', () => {
  it('sends connect_request with device info after socket open', () => {
    const socket = createMockSocket()
    const client = createLanClient({
      socketFactory: () => socket,
    })

    client.connectFromQrPayload(
      JSON.stringify({
        version: 1,
        hostId: 'desktop-1',
        hostName: 'MacBook',
        hostIp: '127.0.0.1',
        port: 19090,
        pairToken: 'token-1',
        expiresAt: '2026-04-24T12:00:00.000Z',
      }),
      {
        deviceId: 'mobile-1',
        deviceName: 'Pixel',
        deviceType: 'mobile',
      },
    )

    socket.emitOpen()

    expect(socket.sent).toHaveLength(1)
    expect(JSON.parse(socket.sent[0] ?? '{}')).toMatchObject({
      type: 'connect_request',
      payload: {
        deviceId: 'mobile-1',
        pairToken: 'token-1',
      },
    })
    expect(client.status.value).toBe('pending')
  })

  it('enters connected state when host approves the request', () => {
    const socket = createMockSocket()
    const client = createLanClient({
      socketFactory: () => socket,
    })

    client.connectFromQrPayload(
      JSON.stringify({
        version: 1,
        hostId: 'desktop-1',
        hostName: 'MacBook',
        hostIp: '127.0.0.1',
        port: 19090,
        pairToken: 'token-1',
        expiresAt: '2026-04-24T12:00:00.000Z',
      }),
      {
        deviceId: 'mobile-1',
        deviceName: 'Pixel',
        deviceType: 'mobile',
      },
    )

    socket.emitOpen()
    socket.emitMessage({
      type: 'connect_approved',
      payload: {
        sessionId: 'session-1',
        remoteDeviceId: 'desktop-1',
      },
    })

    expect(client.status.value).toBe('connected')
    expect(client.sessionId.value).toBe('session-1')
  })

  it('stores rejection reason when host rejects the request', () => {
    const socket = createMockSocket()
    const client = createLanClient({
      socketFactory: () => socket,
    })

    client.connectFromQrPayload(
      JSON.stringify({
        version: 1,
        hostId: 'desktop-1',
        hostName: 'MacBook',
        hostIp: '127.0.0.1',
        port: 19090,
        pairToken: 'token-1',
        expiresAt: '2026-04-24T12:00:00.000Z',
      }),
      {
        deviceId: 'mobile-1',
        deviceName: 'Pixel',
        deviceType: 'mobile',
      },
    )

    socket.emitOpen()
    socket.emitMessage({
      type: 'connect_rejected',
      payload: {
        reason: 'invalid_pair_token',
      },
    })

    expect(client.status.value).toBe('disconnected')
    expect(client.lastError.value).toBe('invalid_pair_token')
  })

  it('sends transfer_offer and stores last accepted transfer', () => {
    const socket = createMockSocket()
    const client = createLanClient({
      socketFactory: () => socket,
    })

    client.connectFromQrPayload(
      JSON.stringify({
        version: 1,
        hostId: 'desktop-1',
        hostName: 'MacBook',
        hostIp: '127.0.0.1',
        port: 19090,
        pairToken: 'token-1',
        expiresAt: '2026-04-24T12:00:00.000Z',
      }),
      {
        deviceId: 'mobile-1',
        deviceName: 'Pixel',
        deviceType: 'mobile',
      },
    )

    socket.emitOpen()
    socket.emitMessage({
      type: 'connect_approved',
      payload: {
        sessionId: 'session-1',
        remoteDeviceId: 'desktop-1',
      },
    })

    const manifest = createTransferManifest('session-1', [
      { relativePath: 'docs/a.txt', size: 10, kind: 'file' },
    ])

    client.sendTransferOffer(manifest)

    expect(JSON.parse(socket.sent[1] ?? '{}')).toMatchObject({
      type: 'transfer_offer',
      payload: {
        sessionId: 'session-1',
        transferId: manifest.transferId,
      },
    })

    socket.emitMessage({
      type: 'transfer_accept',
      payload: {
        sessionId: 'session-1',
        transferId: manifest.transferId,
      },
    })

    expect(client.lastAcceptedTransfer.value).toMatchObject({
      sessionId: 'session-1',
      transferId: manifest.transferId,
    })
  })

  it('stores transfer rejection from the receiver', () => {
    const socket = createMockSocket()
    const client = createLanClient({
      socketFactory: () => socket,
    })

    client.connectFromQrPayload(
      JSON.stringify({
        version: 1,
        hostId: 'desktop-1',
        hostName: 'MacBook',
        hostIp: '127.0.0.1',
        port: 19090,
        pairToken: 'token-1',
        expiresAt: '2026-04-24T12:00:00.000Z',
      }),
      {
        deviceId: 'mobile-1',
        deviceName: 'Pixel',
        deviceType: 'mobile',
      },
    )

    socket.emitOpen()
    socket.emitMessage({
      type: 'connect_approved',
      payload: {
        sessionId: 'session-1',
        remoteDeviceId: 'desktop-1',
      },
    })

    socket.emitMessage({
      type: 'transfer_reject',
      payload: {
        sessionId: 'session-1',
        transferId: 'transfer-1',
        reason: 'receiver_declined',
      },
    })

    expect(client.lastRejectedTransfer.value).toMatchObject({
      sessionId: 'session-1',
      transferId: 'transfer-1',
      reason: 'receiver_declined',
    })
  })
})
