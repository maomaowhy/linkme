import type { TransferItem } from './transfer'

export type DeviceType = 'desktop' | 'mobile'

export interface ConnectRequestPayload {
  deviceId: string
  deviceName: string
  deviceType: DeviceType
  pairToken: string
}

export interface ConnectApprovedPayload {
  sessionId: string
  remoteDeviceId: string
}

export interface ConnectRejectedPayload {
  reason: 'invalid_pair_token' | 'rejected_by_host'
}

export interface TextMessagePayload {
  sessionId: string
  messageId: string
  text: string
  senderId: string
  sentAt: string
}

export interface TransferOfferPayload {
  sessionId: string
  transferId: string
  itemCount: number
  totalBytes: number
  items: TransferItem[]
}

export interface TransferAcceptPayload {
  sessionId: string
  transferId: string
}

export interface TransferRejectPayload {
  sessionId: string
  transferId: string
  reason: 'receiver_declined'
}

export const createConnectRequestMessage = (payload: ConnectRequestPayload) => ({
  type: 'connect_request' as const,
  payload,
})

export const createConnectApprovedMessage = (payload: ConnectApprovedPayload) => ({
  type: 'connect_approved' as const,
  payload,
})

export const createConnectRejectedMessage = (payload: ConnectRejectedPayload) => ({
  type: 'connect_rejected' as const,
  payload,
})

export const createTextMessage = (payload: TextMessagePayload) => ({
  type: 'text_message' as const,
  payload,
})

export const createTransferOfferMessage = (payload: TransferOfferPayload) => ({
  type: 'transfer_offer' as const,
  payload,
})

export const createTransferAcceptMessage = (payload: TransferAcceptPayload) => ({
  type: 'transfer_accept' as const,
  payload,
})

export const createTransferRejectMessage = (payload: TransferRejectPayload) => ({
  type: 'transfer_reject' as const,
  payload,
})
