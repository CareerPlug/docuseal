<template>
  <div
    v-if="isVisible"
    id="upload_success_toast"
    class="toast toast-bottom toast-end z-50"
    role="status"
    aria-live="polite"
    aria-atomic="true"
  >
    <div class="alert alert-success">
      <IconCircleCheck class="w-6 h-6 flex-none" />
      <span>{{ message }}</span>
    </div>
  </div>
</template>

<script>
import { IconCircleCheck } from '@tabler/icons-vue'

export default {
  name: 'BuilderToast',
  components: {
    IconCircleCheck
  },
  data () {
    return {
      isVisible: false,
      message: '',
      dismissTimeout: null
    }
  },
  beforeUnmount () {
    clearTimeout(this.dismissTimeout)
  },
  methods: {
    show (message, duration = 4000) {
      this.message = message
      this.isVisible = true

      clearTimeout(this.dismissTimeout)

      this.dismissTimeout = setTimeout(() => {
        this.isVisible = false
      }, duration)
    }
  }
}
</script>
