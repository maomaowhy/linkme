import { afterEach, describe, expect, it } from 'vitest'
import { once } from 'node:events'
import type { AddressInfo } from 'node:net'
import { createHostServer } from './app'

describe('createHostServer', () => {
  const activeServers: Array<{ close: () => Promise<void> }> = []

  afterEach(async () => {
    while (activeServers.length > 0) {
      await activeServers.pop()?.close()
    }
  })

  it('responds to cors preflight requests for h5 upload clients', async () => {
    const hostServer = createHostServer()
    hostServer.server.listen(0, '127.0.0.1')
    await once(hostServer.server, 'listening')
    activeServers.push({
      close: () => new Promise((resolve, reject) => hostServer.server.close((error) => (error ? reject(error) : resolve()))),
    })

    const port = (hostServer.server.address() as AddressInfo).port
    const response = await fetch(`http://127.0.0.1:${port}/api/transfers/session/transfer/upload`, {
      method: 'OPTIONS',
      headers: {
        origin: 'http://127.0.0.1:5174',
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'content-type,x-relative-path',
      },
    })

    expect(response.status).toBe(204)
    expect(response.headers.get('access-control-allow-origin')).toBe('*')
    expect(response.headers.get('access-control-allow-methods')).toContain('POST')
    expect(response.headers.get('access-control-allow-headers')).toContain('x-relative-path')
  })
})
