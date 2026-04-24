import { describe, expect, it, vi } from 'vitest'
import { pickFilesFromDom } from './dom-file-picker'

type ListenerMap = Record<string, Array<() => void>>

const createFakeInput = () => {
  const listeners: ListenerMap = {}
  const input = {
    type: '',
    accept: '',
    value: '',
    multiple: false,
    files: [] as File[],
    attributes: {} as Record<string, string>,
    click: vi.fn(),
    addEventListener(name: string, listener: () => void) {
      listeners[name] ??= []
      listeners[name].push(listener)
    },
    setAttribute(name: string, value: string) {
      this.attributes[name] = value
    },
    dispatch(name: string) {
      for (const listener of listeners[name] ?? []) {
        listener()
      }
    },
  }

  return input
}

describe('dom file picker', () => {
  it('creates a clickable native input and resolves selected files', async () => {
    const file = new File(['hello'], 'hello.txt', { type: 'text/plain' })
    const input = createFakeInput()
    const appendInput = vi.fn()
    const removeInput = vi.fn()

    const resultPromise = pickFilesFromDom(
      { multiple: true },
      {
        createInput: () => input,
        appendInput,
        removeInput,
      },
    )

    input.files = [file]
    input.dispatch('change')

    const result = await resultPromise

    expect(input.click).toHaveBeenCalledTimes(1)
    expect(input.multiple).toBe(true)
    expect(appendInput).toHaveBeenCalledWith(input)
    expect(removeInput).toHaveBeenCalledWith(input)
    expect(result).toEqual([file])
  })

  it('marks directory picking inputs with webkitdirectory', async () => {
    const input = createFakeInput()

    const resultPromise = pickFilesFromDom(
      { directory: true },
      {
        createInput: () => input,
      },
    )

    input.dispatch('cancel')
    await resultPromise

    expect(input.attributes.webkitdirectory).toBe('')
  })
})
