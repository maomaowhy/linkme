<template>
  <scroll-view scroll-y class="page">
    <view class="panel">
      <text class="title">Link Me Mobile</text>
      <view class="actions">
        <button type="primary" @click="openScan">扫码</button>
        <button type="default" :disabled="!qrPayload.trim()" @click="connectToHost">连接桌面端</button>
        <button type="warn" :disabled="connectionStatus === 'idle'" @click="disconnectFromHost">断开</button>
      </view>
      <view class="field">
        <text class="label">连接二维码内容</text>
        <textarea v-model="qrPayload" class="textarea" :maxlength="-1" auto-height placeholder="扫码后自动填充，或手动粘贴桌面端二维码内容" />
      </view>
      <text class="status">连接状态：{{ connectionStatus }}</text>
      <text v-if="scanError" class="error">扫码错误：{{ scanError }}</text>
      <text v-if="lastError" class="error">连接错误：{{ lastError }}</text>
      <text v-if="pushError" class="error">推送状态：{{ pushError }}</text>
      <text v-if="sessionId" class="status">会话：{{ sessionId }}</text>
      <text v-if="isAppPlusRuntime" class="tip">当前 app-plus 已支持扫码与相册二维码识别；原生文件选择/文件夹选择仍待接入。</text>
    </view>

    <view class="panel">
      <text class="title-secondary">选择待推送内容</text>
      <view class="actions">
        <button :disabled="connectionStatus !== 'connected' || !supportsBrowserFilePicker" @click="openFiles">选择文件</button>
        <button :disabled="connectionStatus !== 'connected' || !supportsBrowserFilePicker" @click="openFolder">选择文件夹</button>
        <button :disabled="selectedFiles.length === 0 || connectionStatus !== 'connected' || isSending" @click="sendSelectedFiles">
          {{ isSending ? '等待接收端确认中…' : '开始推送' }}
        </button>
      </view>

      <text v-if="selectedFiles.length === 0" class="tip">还没有选中文件。</text>
      <view v-else class="list">
        <view v-for="file in selectedFiles" :key="file.relativePath" class="list-item">
          <text class="path">{{ file.relativePath }}</text>
          <text class="size">{{ formatBytes(file.size) }}</text>
        </view>
      </view>
    </view>

    <view class="panel">
      <text class="title-secondary">批次结果</text>
      <text v-if="batches.length === 0" class="tip">还没有推送批次。</text>
      <view v-for="batch in batches" :key="batch.manifest.transferId" class="batch-card">
        <view class="batch-header">
          <view class="batch-meta">
            <text class="batch-id">{{ batch.manifest.transferId }}</text>
            <text class="status">状态：{{ batch.result.status }} ｜ 成功 {{ batch.result.summary.successCount }} / 失败 {{ batch.result.summary.failedCount }} / 总计 {{ batch.result.summary.totalCount }}</text>
          </view>
          <button :disabled="batch.result.summary.failedCount === 0 || connectionStatus !== 'connected'" @click="retryFailed(batch.manifest.transferId)">重试失败项</button>
        </view>

        <view class="list result-list">
          <view v-for="item in batch.result.items" :key="item.relativePath" class="list-item result-item">
            <text class="path">{{ item.relativePath }}</text>
            <text>{{ item.status }}</text>
            <text>尝试 {{ item.attempts }} 次</text>
            <text v-if="item.savedPath">保存到：{{ item.savedPath }}</text>
            <text v-else-if="item.error" class="error">失败原因：{{ item.error }}</text>
          </view>
        </view>
      </view>
    </view>
  </scroll-view>

  <H5ScannerOverlay
    :visible="isH5ScannerVisible"
    @close="isH5ScannerVisible = false"
    @detected="onH5ScannerDetected"
    @error="onH5ScannerError"
  />
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { createTransferManifest, type TransferManifest } from '@link-me/shared'
import H5ScannerOverlay from '../../components/H5ScannerOverlay.vue'
import { createLanClient } from '../../services/lan-client'
import { createDeviceIdStore } from '../../services/device-id'
import { pickFilesFromDom } from '../../services/dom-file-picker'
import { retryFailedTransferItems, uploadTransferBatch, type TransferBatchResult } from '../../services/http-transfer'
import { isPickCancelled, pickScanImageFile } from '../../services/scan-picker'
import { scanQrPayloadFromImage, scanQrPayloadFromPath } from '../../services/scan'

type SelectedFile = {
  relativePath: string
  size: number
  file: File
}

type BatchRecord = {
  manifest: TransferManifest
  files: SelectedFile[]
  result: TransferBatchResult
}

type ScanAction = 'camera' | 'album'

const isAppPlusRuntime = typeof (globalThis as { plus?: unknown }).plus !== 'undefined'
const supportsBrowserFilePicker = typeof window !== 'undefined' && typeof document !== 'undefined' && !isAppPlusRuntime

const qrPayload = ref('')
const scanError = ref('')
const pushError = ref('')
const selectedFiles = ref<SelectedFile[]>([])
const batches = ref<BatchRecord[]>([])
const pendingManifest = ref<TransferManifest | null>(null)
const isSending = ref(false)
const isH5ScannerVisible = ref(false)

const createSocketAdapter = (url: string) => {
  if (typeof WebSocket !== 'undefined') {
    const socket = new WebSocket(url)
    return {
      send(data: string) {
        socket.send(data)
      },
      close() {
        socket.close()
      },
      onOpen(listener: () => void) {
        socket.addEventListener('open', listener)
      },
      onMessage(listener: (payload: string) => void) {
        socket.addEventListener('message', (event) => listener(String(event.data)))
      },
      onClose(listener: () => void) {
        socket.addEventListener('close', listener)
      },
      onError(listener: (error: Error) => void) {
        socket.addEventListener('error', () => listener(new Error('socket_error')))
      },
    }
  }

  const socketTask = uni.connectSocket({ url })
  return {
    send(data: string) {
      socketTask.send({ data })
    },
    close() {
      socketTask.close({})
    },
    onOpen(listener: () => void) {
      socketTask.onOpen(() => listener())
    },
    onMessage(listener: (payload: string) => void) {
      socketTask.onMessage((event) => listener(String(event.data)))
    },
    onClose(listener: () => void) {
      socketTask.onClose(() => listener())
    },
    onError(listener: (error: Error) => void) {
      socketTask.onError(() => listener(new Error('socket_error')))
    },
  }
}

const client = createLanClient({
  socketFactory: createSocketAdapter,
})
const deviceIdStore = createDeviceIdStore()

const connectionStatus = computed(() => client.status.value)
const lastError = computed(() => client.lastError.value)
const sessionId = computed(() => client.sessionId.value)

const showUnsupportedMessage = (feature: string) => {
  uni.showToast({
    title: `${feature}在 app-plus 适配中`,
    icon: 'none',
    duration: 2200,
  })
}

const showImageDecodeLoading = () => {
  uni.showLoading({
    title: '图片解析中...',
    mask: true,
  })
}

const hideLoading = () => {
  uni.hideLoading()
}

const readFileFromInput = async () => (await pickFilesFromDom({ accept: 'image/*', capture: 'environment' }))[0] ?? null

const applySelectedFiles = (files: File[]) => {
  selectedFiles.value = files.map((file) => ({
    relativePath: (file as File & { webkitRelativePath?: string }).webkitRelativePath || file.name,
    size: file.size,
    file,
  }))
}

const isUserCancelled = (error: unknown) => {
  const message = typeof error === 'string' ? error : error instanceof Error ? error.message : ''
  return message.toLowerCase().includes('cancel')
}

const chooseScanAction = async (): Promise<ScanAction | null> => {
  try {
    const result = await uni.showActionSheet({
      itemList: ['扫一扫', '从相册选图'],
    })

    return result.tapIndex === 0 ? 'camera' : 'album'
  } catch (error) {
    if (isUserCancelled(error)) {
      return null
    }

    throw error
  }
}

const formatScanError = (error: unknown) => {
  const message = error instanceof Error ? error.message : 'scan_failed'
  if (message === 'qr_not_found') {
    return '未在图片中识别到二维码'
  }

  if (message === 'barcode_detector_not_supported' || message === 'image_decoder_not_supported') {
    return '当前浏览器缺少扫码解码能力，请更换浏览器或改用扫一扫'
  }

  if (message === 'plus_barcode_not_supported') {
    return '当前 app 运行环境不支持图片二维码识别'
  }

  if (message === '未授予相机权限' || message === '未找到可用摄像头' || message === '当前浏览器不支持摄像头扫码') {
    return message
  }

  return message
}

const scanFromAlbumOnAppPlus = async () => {
  const result = await uni.chooseImage({
    count: 1,
    sizeType: ['compressed'],
    sourceType: ['album'],
  })
  const imagePath = result.tempFilePaths?.[0]
  if (!imagePath) {
    return null
  }

  showImageDecodeLoading()
  try {
    return await scanQrPayloadFromPath(imagePath)
  } finally {
    hideLoading()
  }
}

const scanFromAlbumOnH5 = async () => {
  const file = await pickScanImageFile({
    chooseImage: typeof uni.chooseImage === 'function' ? (options) => uni.chooseImage(options) : undefined,
    inputFallback: readFileFromInput,
  })

  if (!file) {
    return null
  }

  showImageDecodeLoading()
  try {
    return await scanQrPayloadFromImage(file)
  } finally {
    hideLoading()
  }
}

const startCameraScan = async () => {
  if (isAppPlusRuntime) {
    const result = await uni.scanCode({
      onlyFromCamera: true,
      scanType: ['qrCode'],
      autoDecodeCharset: true,
    })
    return String(result.result ?? '').trim()
  }

  isH5ScannerVisible.value = true
  return null
}

const openScan = async () => {
  try {
    scanError.value = ''
    const action = await chooseScanAction()
    if (!action) {
      return
    }

    if (action === 'camera') {
      const result = await startCameraScan()
      if (result) {
        qrPayload.value = result
      }
      return
    }

    const albumPayload = isAppPlusRuntime ? await scanFromAlbumOnAppPlus() : await scanFromAlbumOnH5()
    if (albumPayload) {
      qrPayload.value = albumPayload
    }
  } catch (error) {
    if (isPickCancelled(error) || isUserCancelled(error)) {
      return
    }

    scanError.value = formatScanError(error)
  }
}

const onH5ScannerDetected = (payload: string) => {
  isH5ScannerVisible.value = false
  qrPayload.value = payload.trim()
}

const onH5ScannerError = (message: string) => {
  isH5ScannerVisible.value = false
  scanError.value = formatScanError(new Error(message))
}

const connectToHost = () => {
  client.connectFromQrPayload(qrPayload.value, {
    deviceId: deviceIdStore.getOrCreate(),
    deviceName: supportsBrowserFilePicker ? 'Link Me Mobile H5' : 'Link Me Mobile App',
    deviceType: 'mobile',
  })
}

const disconnectFromHost = () => {
  client.disconnect()
  isSending.value = false
  pendingManifest.value = null
}

const openFiles = async () => {
  if (!supportsBrowserFilePicker) {
    showUnsupportedMessage('原生文件选择')
    return
  }

  applySelectedFiles(await pickFilesFromDom({ multiple: true }))
}

const openFolder = async () => {
  if (!supportsBrowserFilePicker) {
    showUnsupportedMessage('原生文件夹选择')
    return
  }

  applySelectedFiles(await pickFilesFromDom({ directory: true }))
}

const loadFileBody = async (files: SelectedFile[], relativePath: string) => {
  const match = files.find((item) => item.relativePath === relativePath)
  if (!match) {
    throw new Error(`missing file: ${relativePath}`)
  }

  return match.file
}

const sendSelectedFiles = async () => {
  if (!supportsBrowserFilePicker) {
    showUnsupportedMessage('原生文件推送')
    return
  }

  if (!client.connectionInfo.value || !sessionId.value || selectedFiles.value.length === 0) {
    return
  }

  const manifest = createTransferManifest(
    sessionId.value,
    selectedFiles.value.map((file) => ({
      relativePath: file.relativePath,
      size: file.size,
      kind: 'file' as const,
    })),
  )

  pushError.value = ''
  pendingManifest.value = manifest
  isSending.value = true
  client.sendTransferOffer(manifest)
}

watch(
  () => client.lastAcceptedTransfer.value,
  async (accepted) => {
    if (!accepted || !pendingManifest.value || !client.connectionInfo.value) {
      return
    }

    if (accepted.transferId !== pendingManifest.value.transferId) {
      return
    }

    const manifest = pendingManifest.value
    const files = [...selectedFiles.value]
    const result = await uploadTransferBatch({
      hostIp: client.connectionInfo.value.hostIp,
      port: client.connectionInfo.value.port,
      manifest,
      fileBodyLoader: (relativePath) => loadFileBody(files, relativePath),
    })

    batches.value = [{ manifest, files, result }, ...batches.value]
    pendingManifest.value = null
    isSending.value = false
  },
)

watch(
  () => client.lastRejectedTransfer.value,
  (rejected) => {
    if (!rejected || !pendingManifest.value) {
      return
    }

    if (rejected.transferId !== pendingManifest.value.transferId) {
      return
    }

    pushError.value = '接收端已拒绝本次推送，请重新选择保存位置后再发起。'
    pendingManifest.value = null
    isSending.value = false
  },
)

const retryFailed = async (transferId: string) => {
  const batch = batches.value.find((item) => item.manifest.transferId === transferId)
  if (!batch || !client.connectionInfo.value) {
    return
  }

  batch.result = await retryFailedTransferItems({
    hostIp: client.connectionInfo.value.hostIp,
    port: client.connectionInfo.value.port,
    manifest: batch.manifest,
    previous: batch.result,
    fileBodyLoader: (relativePath) => loadFileBody(batch.files, relativePath),
  })
}

const formatBytes = (bytes: number) => {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}
</script>

<style scoped lang="scss">
.page {
  height: 100vh;
  padding: 24rpx;
  box-sizing: border-box;
}

.panel,
.batch-card {
  display: flex;
  flex-direction: column;
  gap: 16rpx;
  padding: 24rpx;
  margin-bottom: 24rpx;
  background: #ffffff;
  border-radius: 24rpx;
  box-shadow: 0 8rpx 24rpx rgba(15, 23, 42, 0.06);
}

.title,
.title-secondary,
.batch-id {
  font-size: 34rpx;
  font-weight: 600;
}

.field,
.list,
.result-list,
.batch-meta {
  display: flex;
  flex-direction: column;
  gap: 12rpx;
}

.textarea {
  width: 100%;
  min-height: 180rpx;
  padding: 20rpx;
  background: #f6f8fb;
  border-radius: 16rpx;
  box-sizing: border-box;
}

.actions,
.batch-header {
  display: flex;
  gap: 12rpx;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
}

.list-item,
.result-item {
  display: flex;
  flex-direction: column;
  gap: 6rpx;
  padding: 16rpx;
  background: #f6f8fb;
  border-radius: 16rpx;
}

.label,
.status,
.tip,
.path,
.size,
.error {
  line-height: 1.5;
}

.error {
  color: #dc2626;
}

.tip {
  color: #6b7280;
}
</style>
