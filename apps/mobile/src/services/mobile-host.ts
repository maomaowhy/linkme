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
