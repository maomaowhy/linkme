import { describe, expect, it } from 'vitest'
import { normalizeRelativePath } from './path'

describe('normalizeRelativePath', () => {
  it('normalizes windows separators into posix separators', () => {
    expect(normalizeRelativePath('docs\\a.txt')).toBe('docs/a.txt')
  })

  it('rejects traversal paths', () => {
    expect(() => normalizeRelativePath('../secrets.txt')).toThrow(/traversal/i)
  })
})
