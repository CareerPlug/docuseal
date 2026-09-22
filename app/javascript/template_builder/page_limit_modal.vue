<template>
  <div
    id="page_limit_modal"
    class="modal modal-open items-start !animate-none overflow-y-auto"
    role="status"
    aria-live="polite"
  >
    <div
      class="absolute top-0 bottom-0 right-0 left-0"
      @click.prevent="$emit('close')"
    />
    <div class="modal-box pt-4 pb-6 px-6 mt-20 max-h-none w-full max-w-xl">
      <div class="flex justify-between items-center border-b pb-2 mb-2 font-medium">
        <span class="modal-title">
          {{ t('page_limit_title') }}
        </span>
        <a
          href="#"
          class="text-xl modal-close-button"
          @click.prevent="$emit('close')"
        >&times;</a>
      </div>
      <div>
        <p>
          {{ t('page_limit_body').replace('{page_count}', pageCount) }}
        </p>
        <button
          class="base-button w-full mt-4 modal-save-button"
          @click.prevent="$emit('close')"
        >
          {{ t('page_limit_close') }}
        </button>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'PageLimitModal',
  inject: ['t'],
  props: {
    pageCount: {
      type: Number,
      required: false,
      default: 0
    }
  },
  emits: ['close']
}
</script>
