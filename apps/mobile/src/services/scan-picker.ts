export type ChooseImageResult = {
  tempFiles?: Array<File | { file?: File | null } | null | undefined>
}

export type ChooseImage = (options: {
  count: number
  sizeType?: string[]
  sourceType?: Array<'album' | 'camera'>
}) => Promise<ChooseImageResult>

export type PickScanImageFileOptions = {
  chooseImage?: ChooseImage
  inputFallback?: () => Promise<File | null>
}

const isBrowserFile = (value: unknown): value is File => typeof File !== 'undefined' && value instanceof File

const pickFirstFile = (result: ChooseImageResult) => {
  const first = result.tempFiles?.[0]
  if (!first) {
    return null
  }

  if (isBrowserFile(first)) {
    return first
  }

  if (typeof first === 'object' && first && 'file' in first && isBrowserFile(first.file)) {
    return first.file
  }

  return null
}

export const isPickCancelled = (error: unknown) => {
  const message = typeof error === 'string' ? error : error instanceof Error ? error.message : ''
  return message.toLowerCase().includes('cancel')
}

export const pickScanImageFile = async ({ chooseImage, inputFallback }: PickScanImageFileOptions) => {
  if (chooseImage) {
    try {
      const result = await chooseImage({
        count: 1,
        sizeType: ['compressed'],
        sourceType: ['album', 'camera'],
      })

      return pickFirstFile(result)
    } catch (error) {
      if (isPickCancelled(error)) {
        return null
      }
    }
  }

  if (!inputFallback) {
    return null
  }

  return inputFallback()
}
