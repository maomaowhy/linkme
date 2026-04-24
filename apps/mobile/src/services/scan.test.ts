import { describe, expect, it, vi } from 'vitest'
import { decodeQrPayload, pickBarcodeValue, scanQrPayloadFromImage, scanQrPayloadFromPath } from './scan'

describe('scan service', () => {
  it('returns the first barcode raw value', () => {
    expect(
      pickBarcodeValue([
        { rawValue: '' },
        { rawValue: '  {"hostIp":"127.0.0.1"}  ' },
      ]),
    ).toBe('{"hostIp":"127.0.0.1"}')
  })

  it('decodes qr payload through the provided decoder', async () => {
    const file = new File(['fake'], 'qr.png', { type: 'image/png' })
    const result = await scanQrPayloadFromImage(file, async (input) => {
      expect(input.name).toBe('qr.png')
      return '  qr-payload  '
    })

    expect(result).toBe('qr-payload')
  })

  it('decodes qr payload from an app-plus image path through the provided decoder', async () => {
    const result = await scanQrPayloadFromPath('/tmp/qr.png', async (path) => {
      expect(path).toBe('/tmp/qr.png')
      return '  qr-from-path  '
    })

    expect(result).toBe('qr-from-path')
  })

  it('falls back to js decoder when barcode detector is unsupported', async () => {
    const file = new File(['fake'], 'qr.png', { type: 'image/png' })
    const detectWithBarcodeDetector = vi.fn(async () => {
      throw new Error('barcode_detector_not_supported')
    })
    const decodeWithJsQr = vi.fn(async () => 'qr-from-js')

    const result = await decodeQrPayload(file, {
      detectWithBarcodeDetector,
      decodeWithJsQr,
    })

    expect(result).toBe('qr-from-js')
    expect(decodeWithJsQr).toHaveBeenCalledWith(file)
  })

  it('propagates qr_not_found when all decoders fail to find a code', async () => {
    const file = new File(['fake'], 'qr.png', { type: 'image/png' })

    await expect(
      decodeQrPayload(file, {
        detectWithBarcodeDetector: async () => {
          throw new Error('qr_not_found')
        },
        decodeWithJsQr: async () => {
          throw new Error('qr_not_found')
        },
      }),
    ).rejects.toThrow('qr_not_found')
  })
})
