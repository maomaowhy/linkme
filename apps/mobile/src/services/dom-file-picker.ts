export type FileInputLike = {
  type: string
  accept: string
  multiple: boolean
  value: string
  files?: ArrayLike<File> | null
  click: () => void
  addEventListener: (
    event: 'change' | 'cancel',
    listener: () => void,
    options?: { once?: boolean },
  ) => void
  setAttribute?: (name: string, value: string) => void
  remove?: () => void
  style?: Partial<CSSStyleDeclaration>
}

export type PickFilesFromDomOptions = {
  accept?: string
  multiple?: boolean
  directory?: boolean
  capture?: string
}

export type PickFilesFromDomDeps = {
  appendInput?: (input: FileInputLike) => void
  createInput?: () => FileInputLike
  removeInput?: (input: FileInputLike) => void
}

const defaultCreateInput = () => {
  if (typeof document === 'undefined') {
    throw new Error('dom_file_picker_not_supported')
  }

  const input = document.createElement('input') as HTMLInputElement
  input.type = 'file'
  Object.assign(input.style, {
    position: 'absolute',
    visibility: 'hidden',
    zIndex: '-999',
    width: '0',
    height: '0',
    top: '0',
    left: '0',
  })
  return input
}

const defaultAppendInput = (input: FileInputLike) => {
  if (typeof document === 'undefined') {
    return
  }

  document.body.appendChild(input as HTMLInputElement)
}

const defaultRemoveInput = (input: FileInputLike) => {
  input.remove?.()
}

export const pickFilesFromDom = async (
  options: PickFilesFromDomOptions = {},
  deps: PickFilesFromDomDeps = {},
) => {
  const createInput = deps.createInput ?? defaultCreateInput
  const appendInput = deps.appendInput ?? defaultAppendInput
  const removeInput = deps.removeInput ?? defaultRemoveInput
  const input = createInput()

  input.type = 'file'
  input.accept = options.accept ?? ''
  input.multiple = Boolean(options.multiple || options.directory)

  if (options.capture) {
    input.setAttribute?.('capture', options.capture)
  }

  if (options.directory) {
    input.setAttribute?.('webkitdirectory', '')
  }

  return await new Promise<File[]>((resolve) => {
    const finalize = () => {
      const files = Array.from(input.files ?? [])
      input.value = ''
      removeInput(input)
      resolve(files)
    }

    input.addEventListener('change', finalize, { once: true })
    input.addEventListener('cancel', finalize, { once: true })
    appendInput(input)
    input.click()
  })
}
