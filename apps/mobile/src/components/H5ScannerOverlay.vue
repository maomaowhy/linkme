<template>
  <view v-if="visible" class="overlay">
    <video ref="videoRef" class="preview" autoplay muted playsinline />
    <canvas ref="canvasRef" class="hidden-canvas" />

    <view class="mask">
      <view class="toolbar">
        <text class="title">扫一扫</text>
        <button size="mini" type="default" @click="handleClose">关闭</button>
      </view>

      <view class="scanner-box">
        <view class="corner top-left" />
        <view class="corner top-right" />
        <view class="corner bottom-left" />
        <view class="corner bottom-right" />
        <view class="scan-line" />
      </view>

      <view class="status-panel">
        <view class="status-row">
          <view class="dot" />
          <text class="status-text">{{ statusText }}</text>
        </view>
        <text class="tip">请将二维码放入框内，系统会自动识别</text>
      </view>
    </view>
  </view>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { decodeQrPayloadFromImageData } from '../services/scan'

const props = defineProps<{
  visible: boolean
}>()

const emit = defineEmits<{
  close: []
  detected: [payload: string]
  error: [message: string]
}>()

const videoRef = ref<HTMLVideoElement | null>(null)
const canvasRef = ref<HTMLCanvasElement | null>(null)
const isOpeningCamera = ref(false)
const isDecodingFrame = ref(false)
let mediaStream: MediaStream | null = null
let animationFrameId = 0
let lastScanAt = 0
let barcodeDetector: { detect: (source: ImageBitmapSource) => Promise<Array<{ rawValue?: string | null }>> } | null = null

const statusText = computed(() => {
  if (isOpeningCamera.value) {
    return '打开摄像头中...'
  }

  if (isDecodingFrame.value) {
    return '识别中...'
  }

  return '等待二维码进入扫描框...'
})

const stopStream = () => {
  if (animationFrameId) {
    cancelAnimationFrame(animationFrameId)
    animationFrameId = 0
  }

  mediaStream?.getTracks().forEach((track) => track.stop())
  mediaStream = null

  const video = videoRef.value
  if (video) {
    video.pause()
    video.srcObject = null
  }
}

const normalizeError = (error: unknown) => {
  const message = error instanceof Error ? error.message : String(error ?? '')
  if (message.includes('Permission denied') || message.includes('NotAllowedError')) {
    return '未授予相机权限'
  }

  if (message.includes('NotFoundError') || message.includes('DevicesNotFoundError')) {
    return '未找到可用摄像头'
  }

  if (message.includes('mediaDevices') || message.includes('getUserMedia')) {
    return '当前浏览器不支持摄像头扫码'
  }

  return message || 'h5_scan_failed'
}

const detectWithBarcodeDetector = async (source: ImageBitmapSource) => {
  const BarcodeDetectorCtor = (globalThis as typeof globalThis & {
    BarcodeDetector?: new (options?: { formats?: string[] }) => {
      detect: (source: ImageBitmapSource) => Promise<Array<{ rawValue?: string | null }>>
    }
  }).BarcodeDetector

  if (!BarcodeDetectorCtor) {
    return null
  }

  barcodeDetector ??= new BarcodeDetectorCtor({ formats: ['qr_code'] })
  const codes = await barcodeDetector.detect(source)
  const result = codes.map((item) => item.rawValue?.trim() ?? '').find(Boolean)
  return result || null
}

const scanFrame = async () => {
  const video = videoRef.value
  const canvas = canvasRef.value
  if (!props.visible || !video || !canvas) {
    return
  }

  animationFrameId = requestAnimationFrame(() => {
    void scanFrame()
  })

  if (isOpeningCamera.value || isDecodingFrame.value) {
    return
  }

  const now = Date.now()
  if (now - lastScanAt < 180) {
    return
  }
  lastScanAt = now

  if (video.readyState < 2 || !video.videoWidth || !video.videoHeight) {
    return
  }

  const context = canvas.getContext('2d')
  if (!context) {
    emit('error', '当前浏览器不支持摄像头扫码')
    stopStream()
    return
  }

  canvas.width = video.videoWidth
  canvas.height = video.videoHeight
  context.drawImage(video, 0, 0, canvas.width, canvas.height)

  isDecodingFrame.value = true
  try {
    const barcodeValue = await detectWithBarcodeDetector(canvas)
    if (barcodeValue) {
      stopStream()
      emit('detected', barcodeValue)
      return
    }

    const imageData = context.getImageData(0, 0, canvas.width, canvas.height)
    const payload = decodeQrPayloadFromImageData(imageData)
    stopStream()
    emit('detected', payload)
  } catch (error) {
    if (!(error instanceof Error) || error.message !== 'qr_not_found') {
      stopStream()
      emit('error', normalizeError(error))
    }
  } finally {
    isDecodingFrame.value = false
  }
}

const openCamera = async () => {
  if (!props.visible) {
    return
  }

  if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
    emit('error', '当前浏览器不支持摄像头扫码')
    return
  }

  try {
    isOpeningCamera.value = true
    mediaStream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: { ideal: 'environment' },
      },
      audio: false,
    })

    const video = videoRef.value
    if (!video) {
      throw new Error('video_not_ready')
    }

    video.srcObject = mediaStream
    await video.play()
    void scanFrame()
  } catch (error) {
    stopStream()
    emit('error', normalizeError(error))
  } finally {
    isOpeningCamera.value = false
  }
}

const handleClose = () => {
  stopStream()
  emit('close')
}

watch(
  () => props.visible,
  (visible) => {
    if (visible) {
      void openCamera()
      return
    }

    stopStream()
  },
)

onBeforeUnmount(() => {
  stopStream()
})
</script>

<style scoped lang="scss">
.overlay {
  position: fixed;
  inset: 0;
  z-index: 999;
  background: #000;
}

.preview {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.hidden-canvas {
  display: none;
}

.mask {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: space-between;
  padding: 48rpx 32rpx 72rpx;
  background: linear-gradient(to bottom, rgba(0, 0, 0, 0.45), rgba(0, 0, 0, 0.2), rgba(0, 0, 0, 0.55));
}

.toolbar {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.title {
  color: #fff;
  font-size: 34rpx;
  font-weight: 600;
}

.scanner-box {
  position: relative;
  width: min(70vw, 520rpx);
  height: min(70vw, 520rpx);
  border: 2rpx solid rgba(255, 255, 255, 0.35);
  border-radius: 24rpx;
  background: rgba(255, 255, 255, 0.06);
  overflow: hidden;
}

.corner {
  position: absolute;
  width: 40rpx;
  height: 40rpx;
  border-color: #34d399;
  border-style: solid;
  border-width: 0;
}

.top-left {
  top: 0;
  left: 0;
  border-top-width: 6rpx;
  border-left-width: 6rpx;
}

.top-right {
  top: 0;
  right: 0;
  border-top-width: 6rpx;
  border-right-width: 6rpx;
}

.bottom-left {
  bottom: 0;
  left: 0;
  border-bottom-width: 6rpx;
  border-left-width: 6rpx;
}

.bottom-right {
  right: 0;
  bottom: 0;
  border-right-width: 6rpx;
  border-bottom-width: 6rpx;
}

.scan-line {
  position: absolute;
  left: 24rpx;
  right: 24rpx;
  top: 20%;
  height: 4rpx;
  border-radius: 999rpx;
  background: linear-gradient(90deg, rgba(52, 211, 153, 0), rgba(52, 211, 153, 0.95), rgba(52, 211, 153, 0));
  box-shadow: 0 0 24rpx rgba(52, 211, 153, 0.85);
  animation: scan-line 2.2s linear infinite;
}

.status-panel {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12rpx;
  color: #fff;
}

.status-row {
  display: flex;
  align-items: center;
  gap: 12rpx;
}

.dot {
  width: 16rpx;
  height: 16rpx;
  border-radius: 50%;
  background: #34d399;
  box-shadow: 0 0 18rpx rgba(52, 211, 153, 0.9);
  animation: pulse 1.4s ease-in-out infinite;
}

.status-text {
  font-size: 28rpx;
  font-weight: 500;
}

.tip {
  font-size: 24rpx;
  color: rgba(255, 255, 255, 0.8);
}

@keyframes scan-line {
  0% { transform: translateY(-160%); }
  50% { transform: translateY(300%); }
  100% { transform: translateY(-160%); }
}

@keyframes pulse {
  0%, 100% { transform: scale(0.9); opacity: 0.75; }
  50% { transform: scale(1.15); opacity: 1; }
}
</style>
