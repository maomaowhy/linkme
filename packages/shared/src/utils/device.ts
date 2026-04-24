import type { DeviceType } from '../protocol/messages'

export interface DeviceSummary {
  deviceId: string
  deviceName: string
  deviceType: DeviceType
}

export const formatDeviceLabel = (device: DeviceSummary) => `${device.deviceName} (${device.deviceType})`
