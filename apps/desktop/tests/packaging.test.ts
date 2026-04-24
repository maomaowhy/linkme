import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const currentDir = dirname(fileURLToPath(import.meta.url))

describe('desktop packaging config', () => {
  it('defines build and pack scripts for Electron packaging', () => {
    const packageJson = JSON.parse(
      readFileSync(resolve(currentDir, '../package.json'), 'utf8'),
    ) as {
      main?: string
      scripts?: Record<string, string>
      build?: Record<string, unknown>
    }

    expect(packageJson.main).toBe('dist-electron/main.cjs')
    expect(packageJson.scripts?.['build:main']).toContain('tsup')
    expect(packageJson.scripts?.pack).toContain('electron-builder')
    expect(packageJson.scripts?.['pack:dir']).toContain('electron-builder --dir')
    expect(packageJson.build?.appId).toBe('com.linkme.desktop')
  })
})
