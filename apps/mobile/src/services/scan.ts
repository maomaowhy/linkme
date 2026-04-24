import jsQR from 'jsqr'

type BarcodeLike = { rawValue?: string | null }

export type Decoder = (file: File) => Promise<string>
export type PathDecoder = (path: string) => Promise<string>

type DecodeQrPayloadOptions = {
  detectWithBarcodeDetector?: Decoder
  decodeWithJsQr?: Decoder
}

export const pickBarcodeValue = (barcodes: BarcodeLike[]) => {
  const value = barcodes.map((item) => item.rawValue?.trim() ?? '').find(Boolean)
  if (!value) {
    throw new Error('qr_not_found')
  }

  return value
}

const defaultDecoder: Decoder = async (file) => {
  const BarcodeDetectorCtor = (globalThis as typeof globalThis & {
    BarcodeDetector?: new (options?: { formats?: string[] }) => {
      detect: (source: ImageBitmapSource) => Promise<Array<{ rawValue?: string | null }>>
    }
  }).BarcodeDetector

  if (!BarcodeDetectorCtor || typeof createImageBitmap !== 'function') {
    throw new Error('barcode_detector_not_supported')
  }

  const bitmap = await createImageBitmap(file)
  try {
    const detector = new BarcodeDetectorCtor({ formats: ['qr_code'] })
    const barcodes = await detector.detect(bitmap)
    return pickBarcodeValue(barcodes)
  } finally {
    if ('close' in bitmap && typeof bitmap.close === 'function') {
      bitmap.close()
    }
  }
}

const readImageDataFromFile = async (file: File) => {
  if (typeof document === 'undefined' || typeof Image === 'undefined' || typeof URL === 'undefined') {
    throw new Error('image_decoder_not_supported')
  }

  const image = await new Promise<HTMLImageElement>((resolve, reject) => {
    const objectUrl = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(objectUrl)
      resolve(img)
    }
    img.onerror = () => {
      URL.revokeObjectURL(objectUrl)
      reject(new Error('image_load_failed'))
    }
    img.src = objectUrl
  })

  const canvas = document.createElement('canvas')
  const width = image.naturalWidth || image.width
  const height = image.naturalHeight || image.height
  canvas.width = width
  canvas.height = height

  const context = canvas.getContext('2d')
  if (!context) {
    throw new Error('image_decoder_not_supported')
  }

  context.drawImage(image, 0, 0, width, height)
  return context.getImageData(0, 0, width, height)
}

export const decodeQrPayloadFromImageData = (imageData: { data: Uint8ClampedArray; width: number; height: number }) => {
  const result = jsQR(imageData.data, imageData.width, imageData.height)
  if (!result?.data?.trim()) {
    throw new Error('qr_not_found')
  }

  return result.data.trim()
}

const decodeWithJsQr: Decoder = async (file) => {
  const imageData = await readImageDataFromFile(file)
  return decodeQrPayloadFromImageData(imageData)
}


const defaultPathDecoder: PathDecoder = async (path) => {
  const plusBarcode = (globalThis as typeof globalThis & {
    plus?: {
      barcode?: {
        QR?: number
        scan?: (
          path: string,
          success: (type: number, result: string, file?: string) => void,
          fail: (error?: { message?: string }) => void,
          filters?: number[],
          autoDecodeCharset?: boolean,
        ) => void
      }
    }
  }).plus?.barcode

  if (!plusBarcode?.scan) {
    throw new Error('plus_barcode_not_supported')
  }

  return await new Promise<string>((resolve, reject) => {
    plusBarcode.scan(
      path,
      (_, result) => resolve(String(result ?? '')),
      (error) => reject(new Error(error?.message || 'qr_not_found')),
      typeof plusBarcode.QR === 'number' ? [plusBarcode.QR] : undefined,
      true,
    )
  })
}

const isQrNotFoundError = (error: unknown) => error instanceof Error && error.message === 'qr_not_found'

export const decodeQrPayload = async (file: File, options: DecodeQrPayloadOptions = {}) => {
  const detectWithBarcodeDetector = options.detectWithBarcodeDetector ?? defaultDecoder
  const decodeWithJsFallback = options.decodeWithJsQr ?? decodeWithJsQr

  let detectorError: unknown = null
  try {
    return (await detectWithBarcodeDetector(file)).trim()
  } catch (error) {
    detectorError = error
  }

  try {
    return (await decodeWithJsFallback(file)).trim()
  } catch (error) {
    if (isQrNotFoundError(error)) {
      throw error
    }

    if (detectorError instanceof Error) {
      throw detectorError
    }

    throw error instanceof Error ? error : new Error('scan_failed')
  }
}

export const scanQrPayloadFromImage = async (file: File, decoder: Decoder = decodeQrPayload) => {
  const result = await decoder(file)
  return result.trim()
}

export const scanQrPayloadFromPath = async (path: string, decoder: PathDecoder = defaultPathDecoder) => {
  const result = await decoder(path)
  return result.trim()
}
