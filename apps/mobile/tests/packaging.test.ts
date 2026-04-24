import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const currentDir = dirname(fileURLToPath(import.meta.url))
const mobileRoot = resolve(currentDir, '..')

describe('mobile uni-app packaging config', () => {
  it('defines official uni-app scripts and plugin dependencies', () => {
    const packageJson = JSON.parse(readFileSync(resolve(mobileRoot, 'package.json'), 'utf8')) as {
      scripts?: Record<string, string>
      dependencies?: Record<string, string>
      devDependencies?: Record<string, string>
    }

    expect(packageJson.scripts?.['dev:h5']).toContain('uni')
    expect(packageJson.scripts?.['build:h5']).toContain('uni build')
    expect(packageJson.scripts?.['build:app-plus'] ?? packageJson.scripts?.['build:app']).toContain('uni build')
    expect(packageJson.dependencies?.['@dcloudio/uni-app']).toBeTruthy()
    expect(packageJson.devDependencies?.['@dcloudio/vite-plugin-uni']).toBeTruthy()
  })

  it('uses createSSRApp entry and includes manifest.json', () => {
    const mainTs = readFileSync(resolve(mobileRoot, 'src/main.ts'), 'utf8')

    expect(mainTs).toContain('createSSRApp')
    expect(existsSync(resolve(mobileRoot, 'src/manifest.json'))).toBe(true)
  })
})
