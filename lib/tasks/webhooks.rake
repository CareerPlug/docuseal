# frozen_string_literal: true

namespace :webhooks do
  desc 'Configure CareerPlug webhook secret from CAREERPLUG_WEBHOOK_SECRET env var'
  task configure_careerplug: :environment do
    secret = ENV.fetch('CAREERPLUG_WEBHOOK_SECRET') do
      if Rails.env.development?
        'development_webhook_secret'
      else
        abort 'CAREERPLUG_WEBHOOK_SECRET environment variable is required'
      end
    end

    webhook_urls = WebhookUrl.where('url LIKE ? OR url LIKE ? OR url LIKE ?',
                                    '%careerplug%', '%cpats%', '%localhost:3000%')

    if webhook_urls.any?
      webhook_urls.find_each do |webhook_url|
        webhook_url.update!(secret: { 'X-CareerPlug-Secret' => secret })
        puts "Updated webhook secret for #{webhook_url.url}"
      end
      puts "Updated #{webhook_urls.count} webhook URL(s)"
    else
      puts 'No CareerPlug webhook URLs found. Available webhooks:'
      WebhookUrl.find_each { |w| puts "  - #{w.id}: #{w.url}" }
    end
  end

  desc 'Set up development webhook URLs for all accounts and partnerships (creates URLs + configures secret)'
  task setup_development: :environment do
    abort 'This task is only for development' unless Rails.env.development?

    url = 'http://localhost:3000/api/docuseal/events'
    secret = { 'X-CareerPlug-Secret' => 'development_webhook_secret' }
    sha1 = Digest::SHA1.hexdigest(url)
    account_events = %w[form.started form.completed submission.completed
                        form.changes_requested template.preferences_updated]
    partnership_events = %w[template.preferences_updated]

    created = 0
    updated = 0

    Account.find_each do |account|
      webhook_url = WebhookUrl.find_or_initialize_by(account:, sha1:)

      if webhook_url.new_record?
        webhook_url.assign_attributes(url:, events: account_events, secret:)
        webhook_url.save!
        created += 1
        puts "Created webhook URL for account #{account.id}: #{account.name}"
      elsif webhook_url.secret != secret
        webhook_url.update!(secret:)
        updated += 1
        puts "Updated webhook secret for account #{account.id}: #{account.name}"
      end
    end

    Partnership.find_each do |partnership|
      webhook_url = WebhookUrl.find_or_initialize_by(partnership:, sha1:)

      if webhook_url.new_record?
        webhook_url.assign_attributes(url:, events: partnership_events, secret:)
        webhook_url.save!
        created += 1
        puts "Created webhook URL for partnership #{partnership.id}: #{partnership.name}"
      elsif webhook_url.secret != secret
        webhook_url.update!(secret:)
        updated += 1
        puts "Updated webhook secret for partnership #{partnership.id}: #{partnership.name}"
      end
    end

    puts "Done: #{created} created, #{updated} updated"
  end

  desc 'Backfill account webhook URLs to include required ATS events'
  task backfill_account_events: :environment do
    required_events = %w[form.started form.completed submission.completed
                         form.changes_requested template.preferences_updated]

    updated = 0

    WebhookUrl.where(partnership_id: nil).find_each do |webhook_url|
      missing = required_events - webhook_url.events

      next if missing.empty?

      webhook_url.update!(events: (webhook_url.events + missing).uniq)
      updated += 1
      puts "Updated account_id=#{webhook_url.account_id} id=#{webhook_url.id}: added #{missing.join(', ')}"
    end

    puts "Done: #{updated} webhook URL(s) updated"
  end
end
