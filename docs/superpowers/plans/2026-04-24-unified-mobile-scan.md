# Unified Mobile Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single scan entry that supports `H5` and `app-plus` with action sheet, live H5 camera scanning, and album image decoding.

**Architecture:** Keep the page as the orchestration layer, move platform-specific picking/decoding into services, and isolate the H5 live scanner into a focused overlay component. Reuse the existing image decode pipeline and extend it for `app-plus` local file paths.

**Tech Stack:** `uni-app`, Vue 3 SFCs, `uni.showActionSheet`, `uni.scanCode`, `uni.chooseImage`, `plus.barcode`, browser `getUserMedia`, `jsqr`, Vitest

---

### Task 1: Extend scan services for app-plus image decoding

**Files:**
- Modify: `apps/mobile/src/services/scan.ts`
- Test: `apps/mobile/src/services/scan.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
it('decodes qr payload from an app-plus image path through the provided decoder', async () => {
  const result = await scanQrPayloadFromPath('/tmp/qr.png', async (path) => {
    expect(path).toBe('/tmp/qr.png')
    return '  qr-from-path  '
  })

  expect(result).toBe('qr-from-path')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @link-me/mobile test src/services/scan.test.ts`
Expected: FAIL because `scanQrPayloadFromPath` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
export type PathDecoder = (path: string) => Promise<string>

export const scanQrPayloadFromPath = async (path: string, decoder: PathDecoder = defaultPathDecoder) => {
  const result = await decoder(path)
  return result.trim()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @link-me/mobile test src/services/scan.test.ts`
Expected: PASS

### Task 2: Build H5 live scanner overlay component

**Files:**
- Create: `apps/mobile/src/components/H5ScannerOverlay.vue`
- Modify: `apps/mobile/src/services/scan.ts`

- [ ] **Step 1: Add the component shell and events**

```vue
<template>
  <view v-if="visible" class="overlay">...</view>
</template>

<script setup lang="ts">
const emit = defineEmits<{
  close: []
  detected: [payload: string]
  error: [message: string]
}>()
</script>
```

- [ ] **Step 2: Implement camera startup and frame loop**

```ts
const stream = await navigator.mediaDevices.getUserMedia({
  video: { facingMode: { ideal: 'environment' } },
  audio: false,
})
```

- [ ] **Step 3: Decode frames and emit result**

```ts
const imageData = context.getImageData(0, 0, width, height)
const result = decodeQrPayloadFromImageData(imageData)
if (result) emit('detected', result)
```

- [ ] **Step 4: Verify via H5 build**

Run: `pnpm --filter @link-me/mobile build:h5`
Expected: PASS

### Task 3: Replace direct scan button logic with unified action sheet flow

**Files:**
- Modify: `apps/mobile/src/pages/index/index.vue`
- Modify: `apps/mobile/src/services/scan-picker.ts`

- [ ] **Step 1: Add action sheet orchestration**

```ts
const chooseScanAction = async () => {
  const result = await uni.showActionSheet({ itemList: ['扫一扫', '从相册选图'] })
  return result.tapIndex === 0 ? 'camera' : 'album'
}
```

- [ ] **Step 2: Wire app-plus branch**

```ts
if (isAppPlusRuntime && action === 'camera') {
  const result = await uni.scanCode({ onlyFromCamera: true, scanType: ['qrCode'] })
  qrPayload.value = String(result.result).trim()
}
```

- [ ] **Step 3: Wire H5 branch and loading states**

```ts
if (action === 'camera') {
  isH5ScannerVisible.value = true
} else {
  uni.showLoading({ title: '图片解析中...' })
}
```

- [ ] **Step 4: Run focused tests**

Run: `pnpm --filter @link-me/mobile test src/services/scan.test.ts src/services/scan-picker.test.ts src/services/dom-file-picker.test.ts`
Expected: PASS

### Task 4: Update docs to reflect new scan behavior

**Files:**
- Modify: `docs/usage.md`
- Modify: `docs/project-status.md`
- Modify: `docs/feature-overview.md`

- [ ] **Step 1: Update usage wording**
- [ ] **Step 2: Mark app-plus scan as implemented**
- [ ] **Step 3: Note remaining limitations clearly**

### Task 5: Final verification

**Files:**
- Verify only

- [ ] **Step 1: Run service tests**

Run: `pnpm --filter @link-me/mobile test src/services/scan.test.ts src/services/scan-picker.test.ts src/services/dom-file-picker.test.ts`
Expected: PASS

- [ ] **Step 2: Run H5 build**

Run: `pnpm --filter @link-me/mobile build:h5`
Expected: PASS
