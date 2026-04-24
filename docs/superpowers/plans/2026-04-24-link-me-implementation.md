# Link Me Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a monorepo project that ships an Electron desktop host, a Vue 3 + Vite + uni-app Android client, and a shared LAN transfer protocol for text, files, multi-file batches, and folders with approval-based connection control.

**Architecture:** The project uses a monorepo with `apps/desktop`, `apps/mobile`, and `packages/shared`. Control-plane messages flow over `WebSocket`, transfer data flows over `HTTP`, and both apps consume shared protocol types and validation helpers to keep state transitions consistent.

**Tech Stack:** `pnpm` workspace, `TypeScript`, `Vue 3`, `Vite`, `uni-app`, `Electron`, `electron-builder`, `Vitest`, `qrcode`, `ws`, `express`, `zod`

---

## File Structure

### Workspace root
- Create: `package.json` — workspace scripts and shared dev tooling
- Create: `pnpm-workspace.yaml` — workspace package discovery
- Create: `tsconfig.base.json` — shared TypeScript config
- Create: `.gitignore` — dependency/build output ignore rules
- Create: `README.md` — top-level product overview and quick start

### Shared package
- Create: `packages/shared/package.json` — shared package metadata
- Create: `packages/shared/tsconfig.json` — package TS config
- Create: `packages/shared/src/index.ts` — shared exports
- Create: `packages/shared/src/protocol/messages.ts` — WS message union types and builders
- Create: `packages/shared/src/protocol/transfer.ts` — transfer task and manifest models
- Create: `packages/shared/src/protocol/qrcode.ts` — QR payload schema and helpers
- Create: `packages/shared/src/utils/path.ts` — relative path normalization helpers
- Create: `packages/shared/src/utils/device.ts` — device info helpers
- Test: `packages/shared/src/**/*.test.ts` — unit tests for protocol and helpers

### Desktop app
- Create: `apps/desktop/package.json` — Electron app scripts and deps
- Create: `apps/desktop/tsconfig.json` — app TS config
- Create: `apps/desktop/vite.config.ts` — renderer build config
- Create: `apps/desktop/electron/main.ts` — Electron main entry
- Create: `apps/desktop/electron/preload.ts` — secure bridge API
- Create: `apps/desktop/electron/server/app.ts` — Express/WS server bootstrap
- Create: `apps/desktop/electron/server/connection-manager.ts` — pending/active session management
- Create: `apps/desktop/electron/server/transfer-manager.ts` — transfer offer, progress, failure orchestration
- Create: `apps/desktop/electron/server/file-service.ts` — local file enumeration, writes, conflict naming
- Create: `apps/desktop/src/main.ts` — renderer app boot
- Create: `apps/desktop/src/App.vue` — renderer shell
- Create: `apps/desktop/src/stores/host.ts` — host state store
- Create: `apps/desktop/src/components/HostDashboard.vue` — service, QR, approval panel
- Create: `apps/desktop/src/components/SessionView.vue` — message and transfer UI
- Test: `apps/desktop/electron/server/*.test.ts` — unit/integration tests for server managers

### Mobile app
- Create: `apps/mobile/package.json` — uni-app scripts and deps
- Create: `apps/mobile/tsconfig.json` — app TS config
- Create: `apps/mobile/vite.config.ts` — uni-app Vite config
- Create: `apps/mobile/src/main.ts` — app boot
- Create: `apps/mobile/src/App.vue` — global shell
- Create: `apps/mobile/src/pages.json` — page routes
- Create: `apps/mobile/src/pages/index/index.vue` — connect/receive entry page
- Create: `apps/mobile/src/pages/session/session.vue` — active session page
- Create: `apps/mobile/src/pages/receive/receive.vue` — Phase 2 receive-mode page
- Create: `apps/mobile/src/stores/session.ts` — session and transfer state
- Create: `apps/mobile/src/services/ws-client.ts` — WS client adapter
- Create: `apps/mobile/src/services/http-transfer.ts` — upload/download adapter
- Create: `apps/mobile/src/services/file-picker.ts` — file/folder selection adapter
- Create: `apps/mobile/src/services/scan.ts` — QR scan adapter
- Create: `apps/mobile/src/services/mobile-host.ts` — Phase 2 host service abstraction
- Test: `apps/mobile/src/services/*.test.ts` — unit tests for protocol adapters

### Documentation
- Create: `docs/feature-overview.md` — complete feature list and behavior notes
- Create: `docs/usage.md` — end-user usage guide
- Create: `docs/build.md` — packaging/build instructions for desktop and Android

---

### Task 1: Scaffold the workspace

**Files:**
- Create: `package.json`
- Create: `pnpm-workspace.yaml`
- Create: `tsconfig.base.json`
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Write the failing workspace smoke test**

Create `package.json` with a temporary failing `test:smoke` script:

```json
{
  "name": "link-me",
  "private": true,
  "packageManager": "pnpm@10.0.0",
  "scripts": {
    "test:smoke": "node -e \"process.exit(1)\""
  }
}
```

- [ ] **Step 2: Run the smoke test to verify failure**

Run: `pnpm test:smoke`
Expected: process exits with code `1`

- [ ] **Step 3: Replace the failing scaffold with the real workspace files**

Create the root files with this content:

`package.json`
```json
{
  "name": "link-me",
  "private": true,
  "packageManager": "pnpm@10.0.0",
  "scripts": {
    "dev:desktop": "pnpm --filter @link-me/desktop dev",
    "dev:mobile": "pnpm --filter @link-me/mobile dev",
    "build:shared": "pnpm --filter @link-me/shared build",
    "build:desktop": "pnpm --filter @link-me/desktop build",
    "build:mobile": "pnpm --filter @link-me/mobile build:app",
    "test": "pnpm -r test"
  },
  "devDependencies": {
    "typescript": "^5.8.3",
    "vitest": "^3.2.4"
  }
}
```

`pnpm-workspace.yaml`
```yaml
packages:
  - apps/*
  - packages/*
```

`tsconfig.base.json`
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "baseUrl": ".",
    "paths": {
      "@link-me/shared": ["packages/shared/src/index.ts"],
      "@link-me/shared/*": ["packages/shared/src/*"]
    }
  }
}
```

`.gitignore`
```gitignore
node_modules
.pnpm-store
.DS_Store
dist
build
out
coverage
.uni
.hbuilderx
```

`README.md`
```md
# Link Me

局域网多端互传项目。

- 桌面端：Electron
- 移动端：Vue 3 + Vite + uni-app (Android)
- 协议：WebSocket 控制 + HTTP 传输
```

- [ ] **Step 4: Run the smoke verification**

Run: `pnpm test`
Expected: command finishes successfully even if child packages are not created yet, or only reports missing package tests after the next task. If the root script fails because no subpackages exist, run `pnpm install` first and then continue with Task 2.

---

### Task 2: Build and test the shared protocol package

**Files:**
- Create: `packages/shared/package.json`
- Create: `packages/shared/tsconfig.json`
- Create: `packages/shared/src/index.ts`
- Create: `packages/shared/src/protocol/messages.ts`
- Create: `packages/shared/src/protocol/transfer.ts`
- Create: `packages/shared/src/protocol/qrcode.ts`
- Create: `packages/shared/src/utils/path.ts`
- Create: `packages/shared/src/utils/device.ts`
- Test: `packages/shared/src/protocol/messages.test.ts`
- Test: `packages/shared/src/protocol/qrcode.test.ts`
- Test: `packages/shared/src/utils/path.test.ts`

- [ ] **Step 1: Write the failing protocol tests**

Create `packages/shared/src/protocol/messages.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { createConnectApprovedMessage, createConnectRequestMessage } from './messages'

describe('protocol messages', () => {
  it('creates a connect request with device metadata', () => {
    const message = createConnectRequestMessage({
      deviceId: 'mobile-1',
      deviceName: 'Pixel',
      deviceType: 'mobile',
    })

    expect(message.type).toBe('connect_request')
    expect(message.payload.deviceId).toBe('mobile-1')
    expect(message.payload.deviceType).toBe('mobile')
  })

  it('creates an approval message with session id', () => {
    const message = createConnectApprovedMessage({
      sessionId: 'session-1',
      remoteDeviceId: 'mobile-1',
    })

    expect(message.type).toBe('connect_approved')
    expect(message.payload.sessionId).toBe('session-1')
  })
})
```

Create `packages/shared/src/protocol/qrcode.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { parseQrPayload, stringifyQrPayload } from './qrcode'

describe('qr payload', () => {
  it('round-trips a valid host payload', () => {
    const encoded = stringifyQrPayload({
      version: 1,
      hostId: 'desktop-1',
      hostName: 'MacBook',
      hostIp: '192.168.1.8',
      port: 19090,
      pairToken: 'token-1',
      expiresAt: '2026-04-24T12:00:00.000Z',
    })

    const parsed = parseQrPayload(encoded)
    expect(parsed.hostIp).toBe('192.168.1.8')
    expect(parsed.port).toBe(19090)
  })
})
```

Create `packages/shared/src/utils/path.test.ts`:

```ts
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
```

- [ ] **Step 2: Run the shared tests to verify failure**

Run: `pnpm exec vitest run packages/shared/src/protocol/messages.test.ts packages/shared/src/protocol/qrcode.test.ts packages/shared/src/utils/path.test.ts`
Expected: FAIL because the imported modules do not exist yet

- [ ] **Step 3: Implement the shared package minimally**

Create `packages/shared/package.json`:

```json
{
  "name": "@link-me/shared",
  "version": "0.1.0",
  "type": "module",
  "main": "src/index.ts",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test": "vitest run"
  },
  "dependencies": {
    "zod": "^3.24.3"
  }
}
```

Create `packages/shared/tsconfig.json`:

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist"
  },
  "include": ["src"]
}
```

Create `packages/shared/src/protocol/messages.ts`:

```ts
export type DeviceType = 'desktop' | 'mobile'

export interface ConnectRequestPayload {
  deviceId: string
  deviceName: string
  deviceType: DeviceType
}

export interface ConnectApprovedPayload {
  sessionId: string
  remoteDeviceId: string
}

export const createConnectRequestMessage = (payload: ConnectRequestPayload) => ({
  type: 'connect_request' as const,
  payload,
})

export const createConnectApprovedMessage = (payload: ConnectApprovedPayload) => ({
  type: 'connect_approved' as const,
  payload,
})
```

Create `packages/shared/src/protocol/qrcode.ts`:

```ts
import { z } from 'zod'

const qrPayloadSchema = z.object({
  version: z.number().int().positive(),
  hostId: z.string().min(1),
  hostName: z.string().min(1),
  hostIp: z.string().min(1),
  port: z.number().int().positive(),
  pairToken: z.string().min(1),
  expiresAt: z.string().datetime(),
})

export type QrPayload = z.infer<typeof qrPayloadSchema>

export const stringifyQrPayload = (payload: QrPayload) => JSON.stringify(payload)

export const parseQrPayload = (value: string): QrPayload => qrPayloadSchema.parse(JSON.parse(value))
```

Create `packages/shared/src/utils/path.ts`:

```ts
export const normalizeRelativePath = (input: string) => {
  const normalized = input.replaceAll('\\', '/').replace(/^\/+/, '')
  if (normalized === '..' || normalized.startsWith('../') || normalized.includes('/../')) {
    throw new Error('path traversal is not allowed')
  }
  return normalized
}
```

Create `packages/shared/src/utils/device.ts`:

```ts
import type { DeviceType } from '../protocol/messages'

export interface DeviceSummary {
  deviceId: string
  deviceName: string
  deviceType: DeviceType
}

export const formatDeviceLabel = (device: DeviceSummary) => `${device.deviceName} (${device.deviceType})`
```

Create `packages/shared/src/protocol/transfer.ts`:

```ts
export interface TransferItem {
  relativePath: string
  size: number
  kind: 'file'
}

export interface TransferManifest {
  transferId: string
  sessionId: string
  items: TransferItem[]
}
```

Create `packages/shared/src/index.ts`:

```ts
export * from './protocol/messages'
export * from './protocol/qrcode'
export * from './protocol/transfer'
export * from './utils/device'
export * from './utils/path'
```

- [ ] **Step 4: Run the shared tests to verify success**

Run: `pnpm --filter @link-me/shared test`
Expected: PASS for all shared tests

---

### Task 3: Create the desktop host server core

**Files:**
- Create: `apps/desktop/package.json`
- Create: `apps/desktop/tsconfig.json`
- Create: `apps/desktop/electron/server/connection-manager.ts`
- Create: `apps/desktop/electron/server/transfer-manager.ts`
- Create: `apps/desktop/electron/server/file-service.ts`
- Create: `apps/desktop/electron/server/app.ts`
- Test: `apps/desktop/electron/server/connection-manager.test.ts`
- Test: `apps/desktop/electron/server/transfer-manager.test.ts`

- [ ] **Step 1: Write the failing host manager tests**

Create `apps/desktop/electron/server/connection-manager.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { ConnectionManager } from './connection-manager'

describe('ConnectionManager', () => {
  it('stores pending connection requests before approval', () => {
    const manager = new ConnectionManager()

    const requestId = manager.addPending({
      deviceId: 'mobile-1',
      deviceName: 'Pixel',
      deviceType: 'mobile',
      socketId: 'socket-1',
    })

    expect(manager.listPending()).toHaveLength(1)
    expect(manager.listPending()[0]?.requestId).toBe(requestId)
  })

  it('moves a pending request to active session when approved', () => {
    const manager = new ConnectionManager()
    const requestId = manager.addPending({
      deviceId: 'mobile-1',
      deviceName: 'Pixel',
      deviceType: 'mobile',
      socketId: 'socket-1',
    })

    const session = manager.approve(requestId)

    expect(session.status).toBe('connected')
    expect(manager.listPending()).toHaveLength(0)
    expect(manager.listSessions()).toHaveLength(1)
  })
})
```

Create `apps/desktop/electron/server/transfer-manager.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { TransferManager } from './transfer-manager'

describe('TransferManager', () => {
  it('creates an offered transfer in waiting state', () => {
    const manager = new TransferManager()

    const transfer = manager.createOffer({
      sessionId: 'session-1',
      direction: 'outbound',
      items: [{ relativePath: 'docs/a.txt', size: 12, kind: 'file' }],
    })

    expect(transfer.status).toBe('offered')
    expect(manager.listBySession('session-1')).toHaveLength(1)
  })
})
```

- [ ] **Step 2: Run the desktop server tests to verify failure**

Run: `pnpm exec vitest run apps/desktop/electron/server/connection-manager.test.ts apps/desktop/electron/server/transfer-manager.test.ts`
Expected: FAIL because server files do not exist yet

- [ ] **Step 3: Implement the minimal desktop server core**

Create `apps/desktop/package.json`:

```json
{
  "name": "@link-me/desktop",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "test": "vitest run"
  },
  "dependencies": {
    "@link-me/shared": "workspace:*",
    "express": "^4.21.2",
    "qrcode": "^1.5.4",
    "ws": "^8.18.1"
  }
}
```

Create `apps/desktop/tsconfig.json`:

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "types": ["node"]
  },
  "include": ["electron", "src", "vite.config.ts"]
}
```

Create `apps/desktop/electron/server/connection-manager.ts`:

```ts
import { randomUUID } from 'node:crypto'
import type { DeviceType } from '@link-me/shared'

interface PendingConnection {
  requestId: string
  deviceId: string
  deviceName: string
  deviceType: DeviceType
  socketId: string
}

interface Session {
  sessionId: string
  remoteDeviceId: string
  remoteDeviceName: string
  remoteDeviceType: DeviceType
  socketId: string
  status: 'connected' | 'disconnected'
}

export class ConnectionManager {
  private pending = new Map<string, PendingConnection>()
  private sessions = new Map<string, Session>()

  addPending(input: Omit<PendingConnection, 'requestId'>) {
    const requestId = randomUUID()
    this.pending.set(requestId, { requestId, ...input })
    return requestId
  }

  listPending() {
    return [...this.pending.values()]
  }

  approve(requestId: string) {
    const pending = this.pending.get(requestId)
    if (!pending) throw new Error('pending request not found')

    this.pending.delete(requestId)

    const session: Session = {
      sessionId: randomUUID(),
      remoteDeviceId: pending.deviceId,
      remoteDeviceName: pending.deviceName,
      remoteDeviceType: pending.deviceType,
      socketId: pending.socketId,
      status: 'connected',
    }

    this.sessions.set(session.sessionId, session)
    return session
  }

  listSessions() {
    return [...this.sessions.values()]
  }
}
```

Create `apps/desktop/electron/server/transfer-manager.ts`:

```ts
import { randomUUID } from 'node:crypto'
import type { TransferItem } from '@link-me/shared'

interface CreateOfferInput {
  sessionId: string
  direction: 'outbound' | 'inbound'
  items: TransferItem[]
}

interface TransferTask extends CreateOfferInput {
  transferId: string
  status: 'offered' | 'accepted' | 'transferring' | 'completed' | 'failed' | 'cancelled'
}

export class TransferManager {
  private transfers = new Map<string, TransferTask[]>()

  createOffer(input: CreateOfferInput): TransferTask {
    const transfer: TransferTask = {
      ...input,
      transferId: randomUUID(),
      status: 'offered',
    }

    const current = this.transfers.get(input.sessionId) ?? []
    current.push(transfer)
    this.transfers.set(input.sessionId, current)
    return transfer
  }

  listBySession(sessionId: string) {
    return this.transfers.get(sessionId) ?? []
  }
}
```

Create `apps/desktop/electron/server/file-service.ts`:

```ts
import { basename, dirname, join } from 'node:path'
import { mkdir, stat } from 'node:fs/promises'

export const ensureDirectory = async (targetDir: string) => {
  await mkdir(targetDir, { recursive: true })
}

export const buildConflictSafePath = async (targetPath: string) => {
  try {
    await stat(targetPath)
  } catch {
    return targetPath
  }

  const parent = dirname(targetPath)
  const name = basename(targetPath)
  return join(parent, `${name}.copy`)
}
```

Create `apps/desktop/electron/server/app.ts`:

```ts
import express from 'express'
import { createServer } from 'node:http'
import { WebSocketServer } from 'ws'

export const createHostServer = () => {
  const app = express()
  const server = createServer(app)
  const websocket = new WebSocketServer({ server })

  app.get('/health', (_req, res) => {
    res.json({ ok: true })
  })

  return { app, server, websocket }
}
```

- [ ] **Step 4: Run the desktop server tests to verify success**

Run: `pnpm --filter @link-me/desktop test`
Expected: PASS for the new server tests

---

### Task 4: Add the desktop Electron shell and renderer UI

**Files:**
- Create: `apps/desktop/vite.config.ts`
- Create: `apps/desktop/electron/main.ts`
- Create: `apps/desktop/electron/preload.ts`
- Create: `apps/desktop/src/main.ts`
- Create: `apps/desktop/src/App.vue`
- Create: `apps/desktop/src/stores/host.ts`
- Create: `apps/desktop/src/components/HostDashboard.vue`
- Create: `apps/desktop/src/components/SessionView.vue`

- [ ] **Step 1: Write the failing host store test**

Create `apps/desktop/src/stores/host.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { createHostStore } from './host'

describe('createHostStore', () => {
  it('records pending devices and active sessions separately', () => {
    const store = createHostStore()

    store.setPending([{ requestId: 'request-1', deviceName: 'Pixel' }])
    store.setSessions([{ sessionId: 'session-1', remoteDeviceName: 'Pixel', status: 'connected' }])

    expect(store.pending.value).toHaveLength(1)
    expect(store.sessions.value).toHaveLength(1)
  })
})
```

- [ ] **Step 2: Run the renderer test to verify failure**

Run: `pnpm exec vitest run apps/desktop/src/stores/host.test.ts`
Expected: FAIL because the renderer store is missing

- [ ] **Step 3: Implement the minimal Electron shell and renderer**

Create `apps/desktop/vite.config.ts`:

```ts
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: { port: 5173 },
})
```

Create `apps/desktop/electron/main.ts`:

```ts
import { BrowserWindow, app } from 'electron'
import { join } from 'node:path'

const createWindow = async () => {
  const window = new BrowserWindow({
    width: 1280,
    height: 840,
    webPreferences: {
      preload: join(__dirname, 'preload.js'),
    },
  })

  if (process.env.VITE_DEV_SERVER_URL) {
    await window.loadURL(process.env.VITE_DEV_SERVER_URL)
    return
  }

  await window.loadFile(join(__dirname, '../dist/index.html'))
}

app.whenReady().then(createWindow)
```

Create `apps/desktop/electron/preload.ts`:

```ts
import { contextBridge } from 'electron'

contextBridge.exposeInMainWorld('linkMe', {
  ping: () => 'pong',
})
```

Create `apps/desktop/src/stores/host.ts`:

```ts
import { ref } from 'vue'

export const createHostStore = () => {
  const pending = ref<{ requestId: string; deviceName: string }[]>([])
  const sessions = ref<{ sessionId: string; remoteDeviceName: string; status: string }[]>([])

  return {
    pending,
    sessions,
    setPending(value: { requestId: string; deviceName: string }[]) {
      pending.value = value
    },
    setSessions(value: { sessionId: string; remoteDeviceName: string; status: string }[]) {
      sessions.value = value
    },
  }
}
```

Create `apps/desktop/src/main.ts`:

```ts
import { createApp } from 'vue'
import App from './App.vue'

createApp(App).mount('#app')
```

Create `apps/desktop/src/App.vue`:

```vue
<template>
  <main class="app-shell">
    <HostDashboard />
    <SessionView />
  </main>
</template>

<script setup lang="ts">
import HostDashboard from './components/HostDashboard.vue'
import SessionView from './components/SessionView.vue'
</script>
```

Create `apps/desktop/src/components/HostDashboard.vue`:

```vue
<template>
  <section>
    <h1>Link Me Host</h1>
    <p>显示二维码、待审批设备、连接状态。</p>
  </section>
</template>
```

Create `apps/desktop/src/components/SessionView.vue`:

```vue
<template>
  <section>
    <h2>当前会话</h2>
    <p>显示文本消息与文件传输任务。</p>
  </section>
</template>
```

- [ ] **Step 4: Run the renderer test to verify success**

Run: `pnpm exec vitest run apps/desktop/src/stores/host.test.ts`
Expected: PASS

---

### Task 5: Create the mobile uni-app client shell and connection flow

**Files:**
- Create: `apps/mobile/package.json`
- Create: `apps/mobile/tsconfig.json`
- Create: `apps/mobile/vite.config.ts`
- Create: `apps/mobile/src/main.ts`
- Create: `apps/mobile/src/App.vue`
- Create: `apps/mobile/src/pages.json`
- Create: `apps/mobile/src/pages/index/index.vue`
- Create: `apps/mobile/src/pages/session/session.vue`
- Create: `apps/mobile/src/stores/session.ts`
- Create: `apps/mobile/src/services/ws-client.ts`
- Create: `apps/mobile/src/services/scan.ts`
- Test: `apps/mobile/src/services/ws-client.test.ts`

- [ ] **Step 1: Write the failing mobile connection test**

Create `apps/mobile/src/services/ws-client.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { createSessionState } from './ws-client'

describe('createSessionState', () => {
  it('starts in idle state and enters pending after connect request', () => {
    const session = createSessionState()

    expect(session.status.value).toBe('idle')
    session.markPendingApproval()
    expect(session.status.value).toBe('pending')
  })
})
```

- [ ] **Step 2: Run the mobile test to verify failure**

Run: `pnpm exec vitest run apps/mobile/src/services/ws-client.test.ts`
Expected: FAIL because the mobile service file is missing

- [ ] **Step 3: Implement the mobile shell and connection state**

Create `apps/mobile/package.json`:

```json
{
  "name": "@link-me/mobile",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build:app": "vite build",
    "test": "vitest run"
  },
  "dependencies": {
    "@link-me/shared": "workspace:*",
    "vue": "^3.5.13"
  }
}
```

Create `apps/mobile/tsconfig.json`:

```json
{
  "extends": "../../tsconfig.base.json",
  "include": ["src", "vite.config.ts"]
}
```

Create `apps/mobile/vite.config.ts`:

```ts
import { defineConfig } from 'vite'

export default defineConfig({
  server: { port: 5174 },
})
```

Create `apps/mobile/src/services/ws-client.ts`:

```ts
import { ref } from 'vue'

export const createSessionState = () => {
  const status = ref<'idle' | 'pending' | 'connected' | 'disconnected'>('idle')

  return {
    status,
    markPendingApproval() {
      status.value = 'pending'
    },
    markConnected() {
      status.value = 'connected'
    },
    markDisconnected() {
      status.value = 'disconnected'
    },
  }
}
```

Create `apps/mobile/src/services/scan.ts`:

```ts
export const parseScanResult = (result: string) => JSON.parse(result)
```

Create `apps/mobile/src/stores/session.ts`:

```ts
import { createSessionState } from '../services/ws-client'

export const createMobileSessionStore = () => createSessionState()
```

Create `apps/mobile/src/main.ts`:

```ts
import App from './App.vue'
export default App
```

Create `apps/mobile/src/App.vue`:

```vue
<template>
  <slot />
</template>
```

Create `apps/mobile/src/pages.json`:

```json
{
  "pages": [
    {
      "path": "pages/index/index",
      "style": {
        "navigationBarTitleText": "Link Me"
      }
    },
    {
      "path": "pages/session/session",
      "style": {
        "navigationBarTitleText": "会话"
      }
    }
  ]
}
```

Create `apps/mobile/src/pages/index/index.vue`:

```vue
<template>
  <view>
    <text>扫码连接桌面端或其他设备</text>
  </view>
</template>
```

Create `apps/mobile/src/pages/session/session.vue`:

```vue
<template>
  <view>
    <text>文本与文件传输会话</text>
  </view>
</template>
```

- [ ] **Step 4: Run the mobile test to verify success**

Run: `pnpm exec vitest run apps/mobile/src/services/ws-client.test.ts`
Expected: PASS

---

### Task 6: Implement transfer manifest generation and acceptance flow

**Files:**
- Modify: `packages/shared/src/protocol/transfer.ts`
- Create: `packages/shared/src/protocol/transfer.test.ts`
- Create: `apps/mobile/src/services/http-transfer.ts`
- Create: `apps/mobile/src/services/file-picker.ts`
- Modify: `apps/desktop/electron/server/transfer-manager.ts`
- Create: `apps/desktop/electron/server/http-upload.test.ts`

- [ ] **Step 1: Write the failing transfer tests**

Create `packages/shared/src/protocol/transfer.test.ts`:

```ts
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
```

Create `apps/desktop/electron/server/http-upload.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { TransferManager } from './transfer-manager'

describe('TransferManager acceptance', () => {
  it('marks an offered transfer as accepted', () => {
    const manager = new TransferManager()
    const transfer = manager.createOffer({
      sessionId: 'session-1',
      direction: 'inbound',
      items: [{ relativePath: 'folder/a.txt', size: 30, kind: 'file' }],
    })

    const accepted = manager.acceptTransfer('session-1', transfer.transferId, '/tmp/save-dir')
    expect(accepted.status).toBe('accepted')
    expect(accepted.targetDirectory).toBe('/tmp/save-dir')
  })
})
```

- [ ] **Step 2: Run the transfer tests to verify failure**

Run: `pnpm exec vitest run packages/shared/src/protocol/transfer.test.ts apps/desktop/electron/server/http-upload.test.ts`
Expected: FAIL because helper and state transition do not exist yet

- [ ] **Step 3: Implement the transfer manifest and accept flow**

Update `packages/shared/src/protocol/transfer.ts`:

```ts
import { randomUUID } from 'node:crypto'

export interface TransferItem {
  relativePath: string
  size: number
  kind: 'file'
}

export interface TransferManifest {
  transferId: string
  sessionId: string
  items: TransferItem[]
  itemCount: number
  totalBytes: number
}

export const createTransferManifest = (sessionId: string, items: TransferItem[]): TransferManifest => ({
  transferId: randomUUID(),
  sessionId,
  items,
  itemCount: items.length,
  totalBytes: items.reduce((sum, item) => sum + item.size, 0),
})
```

Update `apps/desktop/electron/server/transfer-manager.ts`:

```ts
import { randomUUID } from 'node:crypto'
import type { TransferItem } from '@link-me/shared'

interface CreateOfferInput {
  sessionId: string
  direction: 'outbound' | 'inbound'
  items: TransferItem[]
}

interface TransferTask extends CreateOfferInput {
  transferId: string
  status: 'offered' | 'accepted' | 'transferring' | 'completed' | 'failed' | 'cancelled'
  targetDirectory?: string
}

export class TransferManager {
  private transfers = new Map<string, TransferTask[]>()

  createOffer(input: CreateOfferInput): TransferTask {
    const transfer: TransferTask = {
      ...input,
      transferId: randomUUID(),
      status: 'offered',
    }

    const current = this.transfers.get(input.sessionId) ?? []
    current.push(transfer)
    this.transfers.set(input.sessionId, current)
    return transfer
  }

  acceptTransfer(sessionId: string, transferId: string, targetDirectory: string) {
    const current = this.transfers.get(sessionId) ?? []
    const transfer = current.find((item) => item.transferId === transferId)
    if (!transfer) throw new Error('transfer not found')
    transfer.status = 'accepted'
    transfer.targetDirectory = targetDirectory
    return transfer
  }

  listBySession(sessionId: string) {
    return this.transfers.get(sessionId) ?? []
  }
}
```

Create `apps/mobile/src/services/http-transfer.ts`:

```ts
import type { TransferManifest } from '@link-me/shared'

export interface PendingTransferDecision {
  manifest: TransferManifest
  targetDirectory: string
}

export const createPendingTransferDecision = (
  manifest: TransferManifest,
  targetDirectory: string,
): PendingTransferDecision => ({ manifest, targetDirectory })
```

Create `apps/mobile/src/services/file-picker.ts`:

```ts
export interface PickedEntry {
  path: string
  kind: 'file' | 'directory'
}

export const ensurePickedEntries = (entries: PickedEntry[]) => {
  if (entries.length === 0) {
    throw new Error('at least one file or folder must be selected')
  }
  return entries
}
```

- [ ] **Step 4: Run the transfer tests to verify success**

Run: `pnpm exec vitest run packages/shared/src/protocol/transfer.test.ts apps/desktop/electron/server/http-upload.test.ts`
Expected: PASS

---

### Task 7: Wire approval, session UI, and document known Phase 2 gaps

**Files:**
- Modify: `apps/desktop/src/components/HostDashboard.vue`
- Modify: `apps/desktop/src/components/SessionView.vue`
- Modify: `apps/mobile/src/pages/index/index.vue`
- Modify: `apps/mobile/src/pages/session/session.vue`
- Create: `apps/mobile/src/pages/receive/receive.vue`
- Create: `apps/mobile/src/services/mobile-host.ts`
- Create: `docs/feature-overview.md`

- [ ] **Step 1: Write the failing Phase 2 capability test**

Create `apps/mobile/src/services/mobile-host.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { createMobileHostCapability } from './mobile-host'

describe('createMobileHostCapability', () => {
  it('starts disabled and can expose receive mode metadata', () => {
    const capability = createMobileHostCapability()
    expect(capability.enabled.value).toBe(false)

    capability.enable('192.168.1.88', 19090)
    expect(capability.enabled.value).toBe(true)
    expect(capability.hostIp.value).toBe('192.168.1.88')
  })
})
```

- [ ] **Step 2: Run the mobile host test to verify failure**

Run: `pnpm exec vitest run apps/mobile/src/services/mobile-host.test.ts`
Expected: FAIL because the receive-mode service is missing

- [ ] **Step 3: Implement the minimal Phase 2 placeholder and user-facing docs**

Create `apps/mobile/src/services/mobile-host.ts`:

```ts
import { ref } from 'vue'

export const createMobileHostCapability = () => {
  const enabled = ref(false)
  const hostIp = ref('')
  const port = ref(0)

  return {
    enabled,
    hostIp,
    port,
    enable(nextHostIp: string, nextPort: number) {
      enabled.value = true
      hostIp.value = nextHostIp
      port.value = nextPort
    },
  }
}
```

Create `apps/mobile/src/pages/receive/receive.vue`:

```vue
<template>
  <view>
    <text>接收模式（Phase 2 占位页）</text>
  </view>
</template>
```

Update `apps/mobile/src/pages/index/index.vue`:

```vue
<template>
  <view>
    <button>扫码连接</button>
    <button>进入接收模式（开发中）</button>
  </view>
</template>
```

Update `apps/mobile/src/pages/session/session.vue`:

```vue
<template>
  <view>
    <text>会话页</text>
    <button>发送文本</button>
    <button>发送文件</button>
    <button>发送文件夹</button>
  </view>
</template>
```

Update `apps/desktop/src/components/HostDashboard.vue`:

```vue
<template>
  <section>
    <h1>Link Me Host</h1>
    <ul>
      <li>显示二维码</li>
      <li>审批连接请求</li>
      <li>查看在线设备</li>
      <li>主动断开设备</li>
    </ul>
  </section>
</template>
```

Update `apps/desktop/src/components/SessionView.vue`:

```vue
<template>
  <section>
    <h2>当前会话</h2>
    <ul>
      <li>文本消息</li>
      <li>发送文件</li>
      <li>发送文件夹</li>
      <li>查看任务进度</li>
    </ul>
  </section>
</template>
```

Create `docs/feature-overview.md`:

```md
# 功能说明

## 已实现目标
- 桌面 Host 基础架构
- 移动端 Client 基础架构
- 共享协议与任务模型
- 审批式连接模型
- 多文件/文件夹 manifest 建模

## 当前限制
- 手机 Host 为 Phase 2 增量能力
- 首期不支持断点续传
- 首期仅支持局域网 Wi-Fi
```

- [ ] **Step 4: Run the mobile host test to verify success**

Run: `pnpm exec vitest run apps/mobile/src/services/mobile-host.test.ts`
Expected: PASS

---

### Task 8: Write usage and packaging documentation

**Files:**
- Modify: `README.md`
- Create: `docs/usage.md`
- Create: `docs/build.md`

- [ ] **Step 1: Write the failing documentation checklist**

Create a local checklist in `docs/build.md` with this initial incomplete content:

```md
# 打包说明

- [ ] Windows `.exe`
- [ ] macOS `.dmg`
- [ ] Android `.apk`
```

This is intentionally incomplete so the review step has something to fail on.

- [ ] **Step 2: Review the docs and verify they are incomplete**

Run: `rg -n '开发|使用|Windows|macOS|Android|apk|dmg|exe' README.md docs/usage.md docs/build.md`
Expected: missing sections for at least one required topic

- [ ] **Step 3: Replace the incomplete docs with full instructions**

Update `README.md`:

```md
# Link Me

局域网多端互传项目。

## 子应用
- `apps/desktop`：Electron 桌面端
- `apps/mobile`：uni-app Android 端
- `packages/shared`：共享协议与工具

## 主要能力
- 文本互传
- 文件、多文件、文件夹互传
- 连接审批与主动断开
- 多设备会话管理
```

Create `docs/usage.md`:

```md
# 使用说明

## 电脑到手机
1. 打开桌面端并启动服务
2. 手机扫码连接
3. 在桌面端允许连接
4. 进入会话页发送文本、文件或文件夹

## 手机到电脑
1. 手机进入已连接会话
2. 选择文件或文件夹
3. 电脑端选择保存位置并接受任务

## 手机到手机
1. 接收手机进入接收模式（Phase 2）
2. 发送手机扫码连接
3. 接收手机允许连接后开始传输
```

Create `docs/build.md`:

```md
# 打包说明

## 开发环境
- Node.js 20+
- pnpm 10+
- Android Studio（用于 APK 打包）
- HBuilderX 或 uni-app Android 构建链路

## 安装依赖
```bash
pnpm install
```

## 桌面端开发
```bash
pnpm dev:desktop
```

## 移动端开发
```bash
pnpm dev:mobile
```

## Windows `.exe`
使用 `electron-builder` 生成 Windows 安装包。

## macOS `.dmg`
使用 `electron-builder` 生成 macOS 安装包。

## Android `.apk`
使用 uni-app Android 构建流程生成 APK。
```

- [ ] **Step 4: Review the docs to verify completeness**

Run: `rg -n '开发环境|桌面端开发|移动端开发|Windows|macOS|Android|使用说明|手机到手机' README.md docs/usage.md docs/build.md`
Expected: every required topic appears at least once

---

## Self-Review Checklist

### Spec coverage
- Desktop Electron packaging is covered in Tasks 1, 3, 4, and 8.
- Mobile Vue 3 + Vite + uni-app scaffolding is covered in Tasks 1, 5, and 8.
- Shared LAN protocol is covered in Tasks 2 and 6.
- Approval-based multi-device connection flow is covered in Tasks 3, 4, and 7.
- Text/file/folder transfer model is covered in Tasks 2, 5, 6, and 7.
- Product docs, usage docs, and build docs are covered in Tasks 7 and 8.
- Mobile-to-mobile support is represented as the Phase 2 structure in Task 7; the actual runnable host service should be finished after the desktop/mobile baseline is stable.

### Placeholder scan
- This plan does not use `TBD`, `TODO`, or “implement later” placeholders in executable steps.
- The only deferred concept is explicitly labeled `Phase 2`, matching the approved spec.

### Type consistency
- `DeviceType` is defined in `packages/shared/src/protocol/messages.ts` and reused by desktop server code.
- `TransferItem` and `TransferManifest` are defined in `packages/shared/src/protocol/transfer.ts` and reused by desktop/mobile services.
- Session and transfer status names are consistent across tests and implementation steps.
