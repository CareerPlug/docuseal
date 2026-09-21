<template>
  <div>
    <label
      id="add_document_button"
      :for="inputId"
      class="btn btn-outline w-full add-document-button"
      :class="{ 'btn-disabled': isLoading }"
    >
      <IconInnerShadowTop
        v-if="isLoading"
        width="20"
        class="animate-spin"
      />
      <IconUpload
        v-else
        width="20"
      />
      <span v-if="isLoading">
        {{ t('uploading_') }}
      </span>
      <span v-else>
        {{ t('add_document') }}
      </span>
    </label>
    <form
      ref="form"
      class="hidden"
    >
      <input
        :id="inputId"
        ref="input"
        name="files[]"
        type="file"
        :accept="acceptFileTypes"
        multiple
        @change="upload"
      >
    </form>
  </div>
</template>

<script>
import { IconUpload, IconInnerShadowTop } from '@tabler/icons-vue'
import { PAGE_LIMIT, SYNC_SCAN_LIMIT, countPdfPages, countPdfPagesSync, reportBlocked } from '../lib/pdf_page_limit_guard'

export default {
  name: 'DocumentsUpload',
  components: {
    IconUpload,
    IconInnerShadowTop
  },
  inject: ['baseFetch', 't', 'template'],
  props: {
    templateId: {
      type: [Number, String],
      required: true
    },
    acceptFileTypes: {
      type: String,
      required: false,
      default: 'image/*, application/pdf'
    }
  },
  emits: ['success', 'error'],
  data () {
    return {
      isLoading: false
    }
  },
  computed: {
    inputId () {
      return 'el' + Math.random().toString(32).split('.')[1]
    },
    uploadUrl () {
      return `/templates/${this.templateId}/documents`
    }
  },
  methods: {
    async upload () {
      this.isLoading = true

      for (const file of this.$refs.input.files) {
        // Small files scan synchronously so allow-case uploads still dispatch
        // in the change-event task; large files use the async chunked reader.
        const pageCount = file.size <= SYNC_SCAN_LIMIT ? countPdfPagesSync(file) : await countPdfPages(file)

        if (pageCount && pageCount > PAGE_LIMIT) {
          reportBlocked({ pageCount, surface: 'builder', fileSize: file.size })

          this.isLoading = false
          this.$refs.input.value = ''

          window.dispatchEvent(new CustomEvent('docuseal:page-limit-blocked', { detail: { pageCount } }))

          return
        }
      }

      const formData = new FormData(this.$refs.form)
      
      // Add partnership context if available
      if (this.template?.partnership_context) {
        const context = this.template.partnership_context
        if (context.accessible_partnership_ids) {
          context.accessible_partnership_ids.forEach(id => {
            formData.append('accessible_partnership_ids[]', id)
          })
        }
        if (context.external_partnership_id) {
          formData.append('external_partnership_id', context.external_partnership_id)
        }
        if (context.external_account_id) {
          formData.append('external_account_id', context.external_account_id)
        }
      }

      this.baseFetch(this.uploadUrl, {
        method: 'POST',
        headers: { Accept: 'application/json' },
        body: formData
      }).then((resp) => {
        if (resp.ok) {
          resp.json().then((data) => {
            this.$emit('success', data)
            this.$refs.input.value = ''
            this.isLoading = false
          })
        } else if (resp.status === 422) {
          resp.json().then((data) => {
            if (data.status === 'pdf_encrypted') {
              const formData = new FormData(this.$refs.form)

              formData.append('password', prompt(this.t('enter_pdf_password')))
              
              // Add partnership context if available
              if (this.template?.partnership_context) {
                const context = this.template.partnership_context
                if (context.accessible_partnership_ids) {
                  context.accessible_partnership_ids.forEach(id => {
                    formData.append('accessible_partnership_ids[]', id)
                  })
                }
                if (context.external_partnership_id) {
                  formData.append('external_partnership_id', context.external_partnership_id)
                }
                if (context.external_account_id) {
                  formData.append('external_account_id', context.external_account_id)
                }
              }

              this.baseFetch(this.uploadUrl, {
                method: 'POST',
                body: formData
              }).then(async (resp) => {
                if (resp.ok) {
                  this.$emit('success', await resp.json())
                  this.$refs.input.value = ''
                  this.isLoading = false
                } else {
                  alert(this.t('wrong_password'))

                  this.$emit('error', await resp.json().error)
                  this.isLoading = false
                }
              })
            } else {
              this.$emit('error', data.error)
              this.isLoading = false
            }
          })
        } else {
          resp.json().then((data) => {
            this.$emit('error', data.error)
            this.isLoading = false
          })
        }
      }).catch(() => {
        this.isLoading = false
      })
    }
  }
}
</script>
