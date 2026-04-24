import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { buildConflictSafePath, writeTransferFile } from './file-service'

describe('file-service', () => {
  const tempDirs: string[] = []

  afterEach(async () => {
    while (tempDirs.length > 0) {
      const tempDir = tempDirs.pop()
      if (tempDir) {
        await rm(tempDir, { recursive: true, force: true })
      }
    }
  })

  it('auto-renames conflicting files with increment suffixes', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'link-me-file-service-'))
    tempDirs.push(tempDir)

    const docsDir = join(tempDir, 'docs')
    await mkdir(docsDir, { recursive: true })

    const targetPath = join(docsDir, 'hello.txt')
    await writeFile(targetPath, 'first')
    await writeFile(join(docsDir, 'hello (1).txt'), 'second')

    await expect(buildConflictSafePath(targetPath)).resolves.toBe(join(docsDir, 'hello (2).txt'))
  })

  it('writes nested files and keeps both originals via auto-rename', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'link-me-write-file-'))
    tempDirs.push(tempDir)

    const firstPath = await writeTransferFile(tempDir, 'nested/world.txt', Buffer.from('first'))
    const secondPath = await writeTransferFile(tempDir, 'nested/world.txt', Buffer.from('second'))

    expect(firstPath).toBe(join(tempDir, 'nested', 'world.txt'))
    expect(secondPath).toBe(join(tempDir, 'nested', 'world (1).txt'))
  })
})
