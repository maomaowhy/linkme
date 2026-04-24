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
