import { describe, expect, it } from 'vitest'
import { createTransferManifest } from './transfer'

describe('createTransferManifest', () => {
  it('builds a manifest with total size and item count', () => {
    const manifest = createTransferManifest('session-1', [
      { relativePath: 'docs/a.txt', size: 10, kind: 'file' },
      { relativePath: 'docs/b.txt', size: 20, kind: 'file' },
    ])

    expect(manifest.sessionId).toBe('session-1')
    expect(manifest.itemCount).toBe(2)
    expect(manifest.totalBytes).toBe(30)
  })
})
