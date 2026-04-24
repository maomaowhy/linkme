import { computed, ref } from 'vue'

interface HostSession {
  sessionId: string
  remoteDeviceName: string
  status: string
}

interface HostTransferItem {
  relativePath: string
  status: string
  attempts: number
  error?: string
  savedPath?: string
}

interface HostTransferBatch {
  transferId: string
  status: string
  items: HostTransferItem[]
  summary: {
    totalCount: number
    successCount: number
    failedCount: number
  }
}

export const createHostStore = () => {
  const pending = ref<{ requestId: string; deviceName: string }[]>([])
  const sessions = ref<HostSession[]>([])
  const hostInfo = ref<{ hostIp: string; port: number; qrPayload: string } | null>(null)
  const selectedSessionId = ref('')
  const transfersBySession = ref<Record<string, HostTransferBatch[]>>({})

  const currentTransfers = computed(() => {
    if (!selectedSessionId.value) {
      return []
    }

    return transfersBySession.value[selectedSessionId.value] ?? []
  })

  return {
    pending,
    sessions,
    hostInfo,
    selectedSessionId,
    currentTransfers,
    setPending(value: { requestId: string; deviceName: string }[]) {
      pending.value = value
    },
    setSessions(value: HostSession[]) {
      sessions.value = value

      if (!value.some((session) => session.sessionId === selectedSessionId.value)) {
        selectedSessionId.value = value[0]?.sessionId ?? ''
      }
    },
    setTransfers(sessionId: string, transfers: HostTransferBatch[]) {
      transfersBySession.value = {
        ...transfersBySession.value,
        [sessionId]: transfers,
      }
    },
    selectSession(sessionId: string) {
      selectedSessionId.value = sessionId
    },
    setHostInfo(value: { hostIp: string; port: number; qrPayload: string }) {
      hostInfo.value = value
    },
  }
}
