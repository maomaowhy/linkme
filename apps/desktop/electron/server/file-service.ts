import { basename, dirname, extname, join } from 'node:path'
import { mkdir, stat, writeFile } from 'node:fs/promises'
import { normalizeRelativePath } from '@link-me/shared'

export const ensureDirectory = async (targetDir: string) => {
  await mkdir(targetDir, { recursive: true })
}

const appendConflictSuffix = (targetPath: string, index: number) => {
  const extension = extname(targetPath)
  const originalName = basename(targetPath, extension)
  const parent = dirname(targetPath)
  return join(parent, `${originalName} (${index})${extension}`)
}

export const buildConflictSafePath = async (targetPath: string) => {
  try {
    await stat(targetPath)
  } catch {
    return targetPath
  }

  let nextIndex = 1
  while (true) {
    const candidate = appendConflictSuffix(targetPath, nextIndex)
    try {
      await stat(candidate)
      nextIndex += 1
    } catch {
      return candidate
    }
  }
}

export const writeTransferFile = async (targetDirectory: string, relativePath: string, body: Buffer) => {
  const safeRelativePath = normalizeRelativePath(relativePath)
  const targetPath = join(targetDirectory, safeRelativePath)
  await ensureDirectory(dirname(targetPath))
  const finalPath = await buildConflictSafePath(targetPath)
  await writeFile(finalPath, body)
  return finalPath
}
