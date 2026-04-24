<template>
  <section class="host-panel">
    <section v-if="hostInfo" class="panel">
      <h2>桌面 Host</h2>
      <p>地址：{{ hostInfo.hostIp }}:{{ hostInfo.port }}</p>
      <img v-if="qrDataUrl" :src="qrDataUrl" alt="link me qrcode" class="qr-code" />
      <details>
        <summary>二维码内容</summary>
        <pre>{{ hostInfo.qrPayload }}</pre>
      </details>
    </section>

    <section class="panel">
      <header class="panel-actions">
        <h3>待允许设备</h3>
        <button @click="refreshSnapshot">刷新</button>
      </header>
      <p v-if="pending.length === 0">暂无待审批设备。</p>
      <ul v-else>
        <li v-for="item in pending" :key="item.requestId">
          <span>{{ item.deviceName }}</span>
          <button @click="approve(item.requestId)">允许连接</button>
        </li>
      </ul>
    </section>

    <section class="panel">
      <h3>在线会话</h3>
      <p v-if="sessions.length === 0">暂无在线会话。</p>
      <ul v-else>
        <li v-for="session in sessions" :key="session.sessionId">
          <span>{{ session.remoteDeviceName }} · {{ session.status }}</span>
        </li>
      </ul>
    </section>
  </section>
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import QRCode from 'qrcode'

const hostInfo = ref<{ hostIp: string; port: number; qrPayload: string } | null>(null)
const qrDataUrl = ref('')
const pending = ref<Array<{ requestId: string; deviceName: string }>>([])
const sessions = ref<Array<{ sessionId: string; remoteDeviceName: string; status: string }>>([])
let refreshTimer: ReturnType<typeof setInterval> | undefined

const refreshSnapshot = async () => {
  if (!window.linkMe?.host?.getSnapshot) {
    return
  }

  const snapshot = await window.linkMe.host.getSnapshot()
  pending.value = snapshot.pending.map((item) => ({
    requestId: item.requestId,
    deviceName: item.deviceName,
  }))
  sessions.value = snapshot.sessions.map((item) => ({
    sessionId: item.sessionId,
    remoteDeviceName: item.remoteDeviceName,
    status: item.status,
  }))
}

const approve = async (requestId: string) => {
  await window.linkMe?.host?.approve?.(requestId)
  await refreshSnapshot()
}

onMounted(async () => {
  if (!window.linkMe?.host?.getInfo) {
    return
  }

  hostInfo.value = await window.linkMe.host.getInfo()
  qrDataUrl.value = await QRCode.toDataURL(hostInfo.value.qrPayload)
  await refreshSnapshot()
  refreshTimer = setInterval(() => {
    void refreshSnapshot()
  }, 2000)
})

onBeforeUnmount(() => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
  }
})
</script>

<style scoped>
.host-panel {
  display: grid;
  gap: 16px;
}

.qr-code {
  width: 220px;
  height: 220px;
}

.panel {
  border: 1px solid #d0d7de;
  border-radius: 12px;
  padding: 12px;
}

.panel-actions {
  display: flex;
  gap: 8px;
}
</style>
