# frozen_string_literal: true

# CVE-2026-66066: block libvips loaders unsafe for untrusted input.
# Covers Active Storage and first-party Vips::Image.new_from_buffer call sites.
# Requires libvips >= 8.13 and ruby-vips >= 2.2.1.
if defined?(Vips) && Vips.respond_to?(:block_untrusted)
  Vips.block_untrusted(true)
else
  # Fail loudly (but do not block boot) so a missing mitigation cannot be missed
  # in staging/production. Matches careerplug_webhook_config.rb reporting style.
  message = 'Vips.block_untrusted unavailable (libvips < 8.13 or ruby-vips < 2.2.1?) — ' \
            'CVE-2026-66066 mitigation NOT active'
  warn "WARNING: #{message}"

  unless Rails.env.local?
    Rails.logger.error("[vips_block_untrusted] #{message}")
    Airbrake.notify(message)
  end
end
