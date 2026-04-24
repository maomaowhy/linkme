<template>
  <section class="session-layout">
    <header class="toolbar">
      <h2>会话与批次结果</h2>
      <button @click="refreshAll">刷新</button>
    </header>

    <div class="session-layout__body">
      <aside class="session-list">
        <h3>会话列表</h3>
        <p v-if="store.sessions.value.length === 0">暂无已连接会话。</p>
        <ul v-else>
          <li v-for="session in store.sessions.value" :key="session.sessionId">
            <button class="session-button" @click="selectSession(session.sessionId)">
              {{ session.remoteDeviceName }} · {{ session.status }}
            </button>
          </li>
        </ul>
      </aside>

      <main class="transfer-panel">
        <template v-if="selectedSession">
          <div class="transfer-panel__header">
            <h3>{{ selectedSession.remoteDeviceName }}</h3>
            <button @click="disconnectSelected">断开连接</button>
          </div>

          <p v-if="store.currentTransfers.value.length === 0">当前会话还没有批次任务。</p>

          <article v-for="transfer in store.currentTransfers.value" :key="transfer.transferId" class="transfer-card">
            <header class="transfer-card__header">
              <div>
                <strong>{{ transfer.transferId }}</strong>
                <p>
                  状态：{{ transfer.status }} ｜ 成功 {{ transfer.summary.successCount }} / 失败
                  {{ transfer.summary.failedCount }} / 总计 {{ transfer.summary.totalCount }}
                </p>
                <p v-if="transfer.targetDirectory">保存目录：{{ transfer.targetDirectory }}</p>
                <p v-if="transfer.rejectionReason">拒绝原因：{{ transfer.rejectionReason }}</p>
              </div>
              <div class="card-actions">
                <button
                  v-if="transfer.status === 'offered'"
                  @click="acceptTransfer(transfer.transferId)"
                >
                  选择位置并接收
                </button>
                <button
                  v-if="transfer.status === 'offered'"
                  @click="rejectTransfer(transfer.transferId)"
                >
                  拒绝
                </button>
                <button
                  v-if="transfer.summary.failedCount > 0 && transfer.status !== 'offered'"
                  :disabled="transfer.summary.failedCount === 0"
                  @click="retryFailed(transfer.transferId)"
                >
                  重试失败项
                </button>
              </div>
            </header>

            <ul class="transfer-items">
              <li v-for="item in transfer.items" :key="item.relativePath">
                <span>{{ item.relativePath }}</span>
                <span>{{ item.status }}</span>
                <span>尝试 {{ item.attempts }} 次</span>
                <span v-if="item.savedPath">保存到：{{ item.savedPath }}</span>
                <span v-else-if="item.error">失败原因：{{ item.error }}</span>
              </li>
            </ul>
          </article>
        </template>

        <p v-else>请选择一个会话查看批次结果。</p>
      </main>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted } from 'vue'
import { createHostStore } from '../stores/host'

const store = createHostStore()
let refreshTimer: ReturnType<typeof setInterval> | undefined

const selectedSession = computed(() =>
  store.sessions.value.find((session) => session.sessionId === store.selectedSessionId.value),
)

const loadTransfers = async (sessionId: string) => {
  const transfers = (await window.linkMe?.host?.listTransfers?.(sessionId)) ?? []
  store.setTransfers(sessionId, transfers)
}

const refreshAll = async () => {
  const snapshot = await window.linkMe?.host?.getSnapshot?.()
  if (!snapshot) {
    return
  }

  store.setSessions(
    snapshot.sessions.map((item) => ({
      sessionId: item.sessionId,
      remoteDeviceName: item.remoteDeviceName,
      status: item.status,
    })),
  )

  if (store.selectedSessionId.value) {
    await loadTransfers(store.selectedSessionId.value)
  }
}

const selectSession = async (sessionId: string) => {
  store.selectSession(sessionId)
  await loadTransfers(sessionId)
}

const disconnectSelected = async () => {
  if (!store.selectedSessionId.value) {
    return
  }

  await window.linkMe?.host?.disconnect?.(store.selectedSessionId.value)
  await refreshAll()
}

const acceptTransfer = async (transferId: string) => {
  if (!store.selectedSessionId.value) {
    return
  }

  await window.linkMe?.host?.acceptTransfer?.(store.selectedSessionId.value, transferId)
  await loadTransfers(store.selectedSessionId.value)
}

const rejectTransfer = async (transferId: string) => {
  if (!store.selectedSessionId.value) {
    return
  }

  await window.linkMe?.host?.rejectTransfer?.(store.selectedSessionId.value, transferId)
  await loadTransfers(store.selectedSessionId.value)
}

const retryFailed = async (transferId: string) => {
  if (!store.selectedSessionId.value) {
    return
  }

  await window.linkMe?.host?.retryFailedItems?.(store.selectedSessionId.value, transferId)
  await loadTransfers(store.selectedSessionId.value)
}

onMounted(async () => {
  await refreshAll()
  refreshTimer = setInterval(() => {
    void refreshAll()
  }, 2000)
})

onBeforeUnmount(() => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
  }
})
</script>

<style scoped>
.session-layout {
  display: grid;
  gap: 16px;
}

.toolbar,
.transfer-panel__header,
.transfer-card__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.session-layout__body {
  display: grid;
  grid-template-columns: 240px 1fr;
  gap: 16px;
}

.session-list,
.transfer-panel,
.transfer-card {
  border: 1px solid #d0d7de;
  border-radius: 12px;
  padding: 12px;
}

.session-button {
  width: 100%;
  text-align: left;
}

.transfer-items {
  display: grid;
  gap: 8px;
}

.card-actions {
  display: flex;
  gap: 8px;
  align-items: center;
  flex-wrap: wrap;
}
</style>
