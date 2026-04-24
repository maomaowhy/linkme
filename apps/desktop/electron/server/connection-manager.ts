import { randomUUID } from 'node:crypto'
import type { DeviceType } from '@link-me/shared'

interface PendingConnection {
  requestId: string
  deviceId: string
  deviceName: string
  deviceType: DeviceType
  socketId: string
}

interface Session {
  sessionId: string
  remoteDeviceId: string
  remoteDeviceName: string
  remoteDeviceType: DeviceType
  socketId: string
  status: 'connected' | 'disconnected'
}

export class ConnectionManager {
  private pending = new Map<string, PendingConnection>()
  private sessions = new Map<string, Session>()

  addPending(input: Omit<PendingConnection, 'requestId'>) {
    const requestId = randomUUID()
    this.pending.set(requestId, { requestId, ...input })
    return requestId
  }

  listPending() {
    return [...this.pending.values()]
  }

  approve(requestId: string) {
    const pending = this.pending.get(requestId)
    if (!pending) {
      throw new Error('pending request not found')
    }

    this.pending.delete(requestId)

    const session: Session = {
      sessionId: randomUUID(),
      remoteDeviceId: pending.deviceId,
      remoteDeviceName: pending.deviceName,
      remoteDeviceType: pending.deviceType,
      socketId: pending.socketId,
      status: 'connected',
    }

    this.sessions.set(session.sessionId, session)
    return session
  }

  listSessions() {
    return [...this.sessions.values()]
  }

  findSessionBySocketId(socketId: string) {
    return [...this.sessions.values()].find((item) => item.socketId === socketId)
  }

  findSessionById(sessionId: string) {
    return this.sessions.get(sessionId)
  }

  disconnectSession(sessionId: string) {
    const session = this.sessions.get(sessionId)
    if (!session) {
      throw new Error('session not found')
    }

    session.status = 'disconnected'
    return session
  }

  disconnectBySocketId(socketId: string) {
    const session = [...this.sessions.values()].find((item) => item.socketId === socketId)
    if (!session) {
      return undefined
    }

    session.status = 'disconnected'
    return session
  }

  removePendingBySocketId(socketId: string) {
    const pending = [...this.pending.values()].find((item) => item.socketId === socketId)
    if (!pending) {
      return undefined
    }

    this.pending.delete(pending.requestId)
    return pending
  }
}
