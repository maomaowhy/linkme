import { describe, expect, it, vi } from 'vitest'
import { isPickCancelled, pickScanImageFile } from './scan-picker'

describe('scan picker', () => {
  it('uses uni.chooseImage when available', async () => {
    const file = new File(['qr'], 'qr.png', { type: 'image/png' })
    const inputFallback = vi.fn(async () => null)

    const result = await pickScanImageFile({
      chooseImage: async () => ({ tempFiles: [file] }),
      inputFallback,
    })

    expect(result).toBe(file)
    expect(inputFallback).not.toHaveBeenCalled()
  })

  it('falls back to input picker when chooseImage is unavailable', async () => {
    const file = new File(['qr'], 'fallback.png', { type: 'image/png' })

    const result = await pickScanImageFile({
      inputFallback: async () => file,
    })

    expect(result).toBe(file)
  })

  it('does not fall back when user cancels chooseImage', async () => {
    const inputFallback = vi.fn(async () => new File(['x'], 'x.png', { type: 'image/png' }))

    const result = await pickScanImageFile({
      chooseImage: async () => {
        throw new Error('chooseImage:fail cancel')
      },
      inputFallback,
    })

    expect(result).toBeNull()
    expect(inputFallback).not.toHaveBeenCalled()
  })

  it('recognizes cancel-like errors', () => {
    expect(isPickCancelled('chooseImage:fail cancel')).toBe(true)
    expect(isPickCancelled(new Error('chooseImage:fail canceled'))).toBe(true)
    expect(isPickCancelled(new Error('permission denied'))).toBe(false)
  })
})
