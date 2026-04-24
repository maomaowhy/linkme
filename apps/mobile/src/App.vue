<script setup lang="ts">
import { onHide, onLaunch, onShow } from '@dcloudio/uni-app'

onLaunch(() => {
  console.log('Link Me Mobile Launch')
})

onShow(() => {
  console.log('Link Me Mobile Show')
})

onHide(() => {
  console.log('Link Me Mobile Hide')
})
</script>

<style lang="scss">
page {
  background: #f6f8fb;
  color: #1f2329;
}
</style>
