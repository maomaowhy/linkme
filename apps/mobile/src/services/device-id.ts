export type DeviceIdStorage = {
  get(key: string): string
  set(key: string, value: string): void
}

export const DEVICE_ID_STORAGE_KEY = 'link_me_mobile_device_id'

const defaultStorage: DeviceIdStorage = {
  get(key) {
    const value = uni.getStorageSync(key)
    return typeof value === 'string' ? value : ''
  },
  set(key, value) {
    uni.setStorageSync(key, value)
  },
}

const createDeviceId = () => {
  const cryptoApi = globalThis.crypto as Crypto | undefined
  if (typeof cryptoApi?.randomUUID === 'function') {
    return `mobile-${cryptoApi.randomUUID()}`
  }

  return `mobile-${Math.random().toString(36).slice(2)}${Math.random().toString(36).slice(2)}`
}

export const createDeviceIdStore = (storage: DeviceIdStorage = defaultStorage) => ({
  getOrCreate() {
    const storedDeviceId = storage.get(DEVICE_ID_STORAGE_KEY).trim()
    if (storedDeviceId) {
      return storedDeviceId
    }

    const deviceId = createDeviceId()
    storage.set(DEVICE_ID_STORAGE_KEY, deviceId)
    return deviceId
  },
})
