import { z } from 'zod'

const qrPayloadSchema = z.object({
  version: z.number().int().positive(),
  hostId: z.string().min(1),
  hostName: z.string().min(1),
  hostIp: z.string().min(1),
  port: z.number().int().positive(),
  pairToken: z.string().min(1),
  expiresAt: z.string().datetime(),
})

export type QrPayload = z.infer<typeof qrPayloadSchema>

export const stringifyQrPayload = (payload: QrPayload) => JSON.stringify(payload)

export const parseQrPayload = (value: string): QrPayload => qrPayloadSchema.parse(JSON.parse(value))
