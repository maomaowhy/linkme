import { describe, expect, it } from 'vitest'
import { createMobileHostCapability } from './mobile-host'

describe('createMobileHostCapability', () => {
  it('starts disabled and can expose receive mode metadata', () => {
    const capability = createMobileHostCapability()
    expect(capability.enabled.value).toBe(false)

    capability.enable('192.168.1.88', 19090)
    expect(capability.enabled.value).toBe(true)
    expect(capability.hostIp.value).toBe('192.168.1.88')
  })
})
