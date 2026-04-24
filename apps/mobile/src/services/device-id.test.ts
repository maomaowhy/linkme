import { describe, expect, it } from 'vitest'
import { createDeviceIdStore } from './device-id'

describe('device id store', () => {
  it('reuses the stored device id across reads', () => {
    const memory = new Map<string, string>()
    const store = createDeviceIdStore({
      get(key) { return memory.get(key) ?? '' },
      set(key, value) { memory.set(key, value) },
    })
    const first = store.getOrCreate()
    const second = store.getOrCreate()
    expect(first).toBeTruthy()
    expect(second).toBe(first)
  })
})
