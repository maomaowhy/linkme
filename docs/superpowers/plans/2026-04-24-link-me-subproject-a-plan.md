# Link Me Subproject A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete Subproject A flow: stable mobile identity, session reuse, desktop default save directory, Android app-plus multi-file upload, unified progress feedback, then apply the first glassmorphism UI pass.

**Architecture:** Keep transport compatibility with the existing websocket + HTTP upload design, but move identity, save-directory policy, and file-selection logic into focused services. First stabilize behavior at the data and runtime layers, then remap both UIs onto the new workflow, and only after that add the glassmorphism surface styling.

**Tech Stack:** Vue 3, uni-app, Electron, Express, ws, Native.js (Android app-plus), Vitest, H5 browser file APIs

---

### Task 1: Persist stable mobile `deviceId`

**Files:**
- Create: `apps/mobile/src/services/device-id.ts`
- Modify: `apps/mobile/src/pages/index/index.vue`
- Test: `apps/mobile/src/services/device-id.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest'
import { createDeviceIdStore } from './device-id'

describe('device id store', () => {
  it('reuses the stored device id across reads', () => {
    const memory = new Map<string, string>()
    const store = createDeviceIdStore({
      get(key) {
        return memory.get(key) ?? ''
      },
      set(key, value) {
        memory.set(key, value)
      },
    })

    const first = store.getOrCreate()
    const second = store.getOrCreate()

    expect(first).toBeTruthy()
    expect(second).toBe(first)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @link-me/mobile test src/services/device-id.test.ts`
Expected: FAIL because `device-id.ts` does not exist.

- [ ] **Step 3: Write minimal implementation**

```ts
const STORAGE_KEY = 'link_me_mobile_device_id'

export const createDeviceIdStore = (storage = {
  get: (key: string) => uni.getStorageSync(key) as string,
  set: (key: string, value: string) => uni.setStorageSync(key, value),
}) => ({
  getOrCreate() {
    const existing = storage.get(STORAGE_KEY)
    if (existing) return existing
    const next = `mobile-${Math.random().toString(36).slice(2, 10)}`
    storage.set(STORAGE_KEY, next)
    return next
  },
})
```

- [ ] **Step 4: Wire the stable `deviceId` into connect flow**

Use `createDeviceIdStore().getOrCreate()` inside `apps/mobile/src/pages/index/index.vue` so `connectToHost()` no longer uses `Date.now()`.

- [ ] **Step 5: Run test to verify it passes**

Run: `pnpm --filter @link-me/mobile test src/services/device-id.test.ts`
Expected: PASS

### Task 2: Reuse desktop sessions by `deviceId`

**Files:**
- Modify: `apps/desktop/electron/server/connection-manager.ts`
- Modify: `apps/desktop/electron/server/host-service.ts`
- Test: `apps/desktop/electron/server/connection-manager.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
it('reuses an existing session for the same remote device id', () => {
  const manager = new ConnectionManager()
  const firstRequest = manager.addPending({
    deviceId: 'mobile-stable-1',
    deviceName: 'Pixel',
    deviceType: 'mobile',
    socketId: 'socket-a',
  })
  const firstSession = manager.approve(firstRequest)

  manager.disconnectBySocketId('socket-a')

  const secondRequest = manager.addPending({
    deviceId: 'mobile-stable-1',
    deviceName: 'Pixel',
    deviceType: 'mobile',
    socketId: 'socket-b',
  })
  const reused = manager.approve(secondRequest)

  expect(reused.sessionId).toBe(firstSession.sessionId)
  expect(reused.socketId).toBe('socket-b')
  expect(reused.status).toBe('connected')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test electron/server/connection-manager.test.ts`
Workdir: `apps/desktop`
Expected: FAIL because approve always creates a new session today.

- [ ] **Step 3: Implement session reuse**

Update `approve()` in `ConnectionManager` to:
- check existing sessions by `remoteDeviceId`
- reuse the same `sessionId`
- replace `socketId`
- restore `status: 'connected'`
- update device name/type from the latest connect request

- [ ] **Step 4: Mark abandoned running transfers as interrupted on reconnect/disconnect**

Add a new `interruptSessionTransfers(sessionId)` hook in `TransferManager` and call it from the desktop host service when a session disconnects unexpectedly.

- [ ] **Step 5: Run test to verify it passes**

Run: `pnpm test electron/server/connection-manager.test.ts`
Workdir: `apps/desktop`
Expected: PASS

### Task 3: Persist desktop default save directory

**Files:**
- Create: `apps/desktop/electron/server/save-directory-store.ts`
- Modify: `apps/desktop/electron/main.ts`
- Modify: `apps/desktop/electron/server/host-service.ts`
- Test: `apps/desktop/electron/server/save-directory-store.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest'
import { createSaveDirectoryStore } from './save-directory-store'

describe('save directory store', () => {
  it('defaults to desktop and persists user selection', () => {
    const memory = new Map<string, string>()
    const store = createSaveDirectoryStore({
      read: () => memory.get('config') ?? '',
      write: (value) => memory.set('config', value),
      desktopDir: '/Users/demo/Desktop',
    })

    expect(store.get().directory).toBe('/Users/demo/Desktop')
    expect(store.get().confirmed).toBe(false)

    store.set('/Users/demo/Desktop/接收', true)
    expect(store.get()).toEqual({ directory: '/Users/demo/Desktop/接收', confirmed: true })
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test electron/server/save-directory-store.test.ts`
Workdir: `apps/desktop`
Expected: FAIL because store file does not exist.

- [ ] **Step 3: Implement the store**

Create a tiny JSON-backed store with shape:

```ts
export interface SaveDirectoryState {
  directory: string
  confirmed: boolean
}
```

Use Electron `app.getPath('desktop')` as the default directory when there is no saved config.

- [ ] **Step 4: Wire the store into accept-transfer flow**

In `main.ts`, before showing the folder dialog:
- read saved state
- if `confirmed === true`, auto-accept using that directory
- otherwise show a folder dialog and a confirm flow that can persist the chosen folder as default

- [ ] **Step 5: Run test to verify it passes**

Run: `pnpm test electron/server/save-directory-store.test.ts`
Workdir: `apps/desktop`
Expected: PASS

### Task 4: Support transfer interruption and richer progress state

**Files:**
- Modify: `apps/desktop/electron/server/transfer-manager.ts`
- Modify: `apps/mobile/src/services/http-transfer.ts`
- Modify: `apps/mobile/src/pages/index/index.vue`
- Test: `apps/mobile/src/services/http-transfer.test.ts`
- Test: `apps/desktop/electron/server/transfer-manager.test.ts`

- [ ] **Step 1: Write the failing tests**

Add tests for:
- `TransferManager.interruptSessionTransfers(sessionId)` sets running/accepted transfers to `interrupted`
- mobile batch result exposes per-file transfer progress fields needed by UI

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test electron/server/transfer-manager.test.ts`
Workdir: `apps/desktop`
Run: `pnpm --filter @link-me/mobile test src/services/http-transfer.test.ts`
Expected: FAIL because interrupted state and progress fields do not exist.

- [ ] **Step 3: Implement minimal behavior**

Add:
- transfer status `interrupted`
- item field `transferredBytes`
- batch-level progress summary helpers
- UI mapping in mobile page to render “当前批次进度” rather than only final list

- [ ] **Step 4: Run tests to verify they pass**

Run both commands again.
Expected: PASS

### Task 5: Add Android app-plus multi-file picker service

**Files:**
- Create: `apps/mobile/src/services/android-file-picker.ts`
- Modify: `apps/mobile/src/pages/index/index.vue`
- Modify: `apps/mobile/src/services/file-picker.ts`
- Test: `apps/mobile/src/services/android-file-picker.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest'
import { normalizePickedAndroidFiles } from './android-file-picker'

describe('android file picker', () => {
  it('converts picked native files into uploadable entries', () => {
    const result = normalizePickedAndroidFiles([
      { name: 'a.txt', size: 3, path: '/storage/a.txt' },
      { name: 'b.txt', size: 5, path: '/storage/b.txt' },
    ])

    expect(result.map((item) => item.relativePath)).toEqual(['a.txt', 'b.txt'])
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @link-me/mobile test src/services/android-file-picker.test.ts`
Expected: FAIL because service file does not exist.

- [ ] **Step 3: Implement the Android picker**

Use `plus.android.importClass` and Android `Intent.ACTION_OPEN_DOCUMENT` / `ACTION_GET_CONTENT` with multiple selection enabled.
Return normalized entries with:
- `relativePath`
- `size`
- `file`/body loader metadata sufficient for upload

- [ ] **Step 4: Replace app-plus folder/file UI with a single multi-file path**

Remove folder button in `index.vue` and make `选择文件` call:
- H5 -> `pickFilesFromDom({ multiple: true })`
- app-plus Android -> `pickAndroidFiles()`

- [ ] **Step 5: Run test to verify it passes**

Run: `pnpm --filter @link-me/mobile test src/services/android-file-picker.test.ts`
Expected: PASS

### Task 6: Restructure mobile home for the simpler send-first flow

**Files:**
- Modify: `apps/mobile/src/pages/index/index.vue`
- Optionally create: `apps/mobile/src/components/MobileStatusCard.vue`
- Optionally create: `apps/mobile/src/components/MobileTransferProgressCard.vue`

- [ ] **Step 1: Simplify the information hierarchy**

Hide raw QR JSON, session id, and engineer-facing details by default.
Keep only:
- connection card
- `扫码`
- `选择文件`
- `开始发送`
- current transfer progress
- latest result summary

- [ ] **Step 2: Remove folder selection entry**

Delete the folder button and related H5-only folder input code.

- [ ] **Step 3: Render current transfer progress**

Show per-batch progress rather than waiting until the upload is complete.

- [ ] **Step 4: Verify via build**

Run: `pnpm --filter @link-me/mobile build:h5`
Run: `pnpm --filter @link-me/mobile build:app-plus`
Expected: PASS

### Task 7: Restructure desktop home around the send panel

**Files:**
- Modify: `apps/desktop/src/components/SessionView.vue`
- Modify: `apps/desktop/src/components/HostDashboard.vue`
- Modify: `apps/desktop/src/stores/host.ts`

- [ ] **Step 1: Make the selected device the hero block**

Show:
- connected device card
- default save location state
- current transfer progress card
- recent history list

- [ ] **Step 2: Keep session/device management secondary**

Retain the data model but visually demote the session list.

- [ ] **Step 3: Surface default save directory controls**

Add a visible location summary and a clear settings entry point.

- [ ] **Step 4: Verify build**

Run desktop frontend build if present, and `pnpm run build:main`.
Expected: PASS

### Task 8: Apply the first glassmorphism pass

**Files:**
- Modify: `apps/mobile/src/pages/index/index.vue`
- Modify: `apps/mobile/src/uni.scss`
- Modify: `apps/desktop/src/components/SessionView.vue`
- Modify: `apps/desktop/src/App.vue`
- Optionally create shared style helpers inside each app

- [ ] **Step 1: Introduce gradient backgrounds and glass cards**

Use:
- light blue/white gradient page background
- translucent panels
- soft border highlight
- subtle shadow

- [ ] **Step 2: Restyle primary/secondary/danger actions**

Give `扫码`, `选择文件`, `开始发送`, `断开` distinct hierarchy.

- [ ] **Step 3: Keep functionality unchanged**

Only apply the glass layer after the behavior is already green.

- [ ] **Step 4: Verify builds remain green**

Run:
- `pnpm --filter @link-me/mobile build:h5`
- `pnpm --filter @link-me/mobile build:app-plus`
- `pnpm run build:main` in `apps/desktop`
Expected: PASS

### Task 9: Final verification

**Files:**
- Verify only

- [ ] **Step 1: Run mobile tests**

Run: `pnpm --filter @link-me/mobile test src/services/scan.test.ts src/services/scan-picker.test.ts src/services/dom-file-picker.test.ts src/services/device-id.test.ts src/services/android-file-picker.test.ts src/services/http-transfer.test.ts`
Expected: PASS (skip tests for files that do not exist only if they were not needed after implementation changes)

- [ ] **Step 2: Run desktop tests**

Run: `pnpm test electron/server/app.test.ts electron/server/connection-manager.test.ts electron/server/save-directory-store.test.ts electron/server/transfer-manager.test.ts`
Workdir: `apps/desktop`
Expected: PASS

- [ ] **Step 3: Run builds**

Run:
- `pnpm --filter @link-me/mobile build:h5`
- `pnpm --filter @link-me/mobile build:app-plus`
- `pnpm run build:main` in `apps/desktop`
Expected: PASS

- [ ] **Step 4: Prepare manual verification checklist**

Document exact real-device checks for:
- H5 multi-file send
- Android app-plus multi-file send
- first-save dialog
- default-save auto accept
- reconnect with same `deviceId`
- interrupted transfer state
