# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass The initializer is a top-level script, not a class.
RSpec.describe 'careerplug_webhook_config initializer' do
  let(:initializer_path) { Rails.root.join('config/initializers/careerplug_webhook_config.rb').to_s }

  # The initializer is a one-shot top-level script; re-evaluate it under the
  # current stubs to exercise each branch.
  def load_initializer
    load initializer_path
  end

  before do
    allow(Rails.logger).to receive(:error)
    allow(Airbrake).to receive(:notify)
  end

  context 'when not in production' do
    before { allow(Rails.env).to receive(:production?).and_return(false) }

    it 'does not log an error or report to Airbrake' do
      load_initializer

      expect(Rails.logger).not_to have_received(:error)
      expect(Airbrake).not_to have_received(:notify)
    end
  end

  context 'when in production with both vars missing' do
    before do
      allow(Rails.env).to receive(:production?).and_return(true)
      stub_const('ENV', ENV.to_h.except('CAREERPLUG_WEBHOOK_URL', 'CAREERPLUG_WEBHOOK_SECRET'))
    end

    it 'logs a prominent error naming both missing vars' do
      load_initializer

      expect(Rails.logger).to have_received(:error)
        .with(/CareerPlug webhook config missing.*CAREERPLUG_WEBHOOK_URL.*CAREERPLUG_WEBHOOK_SECRET/)
    end

    it 'reports the missing config to Airbrake' do
      load_initializer

      expect(Airbrake).to have_received(:notify).with(/CareerPlug webhook config missing/)
    end
  end

  context 'when in production with only one var missing' do
    before do
      allow(Rails.env).to receive(:production?).and_return(true)
      stub_const('ENV', ENV.to_h.merge('CAREERPLUG_WEBHOOK_URL' => 'https://example.com/events')
                                   .except('CAREERPLUG_WEBHOOK_SECRET'))
    end

    it 'logs an error naming only the missing var' do
      load_initializer

      expect(Rails.logger).to have_received(:error).with(/missing.*CAREERPLUG_WEBHOOK_SECRET/)
    end
  end

  context 'when in production with both vars present' do
    before do
      allow(Rails.env).to receive(:production?).and_return(true)
      stub_const('ENV', ENV.to_h.merge(
                          'CAREERPLUG_WEBHOOK_URL' => 'https://www.careerplug.com/api/docuseal/events',
                          'CAREERPLUG_WEBHOOK_SECRET' => 'secret'
                        ))
    end

    it 'does not log an error or report to Airbrake' do
      load_initializer

      expect(Rails.logger).not_to have_received(:error)
      expect(Airbrake).not_to have_received(:notify)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
