# frozen_string_literal: true

RSpec.describe WebhookRetryLogic do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe '.should_retry?' do
    context 'with successful response' do
      let(:response) { double(status: 200) }

      it 'does not retry' do
        template = create(:template, account: account, author: user)
        result = described_class.should_retry?(response: response, attempt: 1, record: template)
        expect(result).to be false
      end
    end

    context 'with nil response' do
      let(:response) { nil }

      it 'retries within attempt limit' do
        template = create(:template, account: account, author: user)
        result = described_class.should_retry?(response: response, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'does not retry when max attempts exceeded' do
        template = create(:template, account: account, author: user)
        result = described_class.should_retry?(response: response, attempt: 11, record: template)
        expect(result).to be false
      end
    end

    context 'with failed response (status >= 400)' do
      let(:response) { double(status: 500) }

      it 'retries within attempt limit' do
        template = create(:template, account: account, author: user)
        result = described_class.should_retry?(response: response, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'does not retry when max attempts exceeded' do
        template = create(:template, account: account, author: user)
        result = described_class.should_retry?(response: response, attempt: 11, record: template)
        expect(result).to be false
      end
    end

    context 'in non-multitenant mode' do
      before do
        allow(Docuseal).to receive(:multitenant?).and_return(false)
      end

      it 'retries for account templates' do
        template = create(:template, account: account, author: user)
        response = double(status: 500)
        result = described_class.should_retry?(response: response, attempt: 1, record: template)
        expect(result).to be true
      end

      it 'retries for partnership templates' do
        partnership = create(:partnership)
        template = create(:template, partnership: partnership, account: nil, author: user)
        response = double(status: 500)
        result = described_class.should_retry?(response: response, attempt: 1, record: template)
        expect(result).to be true
      end

      it 'retries for submissions' do
        template = create(:template, account: account, author: user)
        submission = create(:submission, template: template, account: account)
        response = double(status: 500)
        result = described_class.should_retry?(response: response, attempt: 1, record: submission)
        expect(result).to be true
      end
    end

    context 'in multitenant mode' do
      before do
        allow(Docuseal).to receive(:multitenant?).and_return(true)
      end

      context 'with account templates' do
        it 'retries if account has plan' do
          create(:account_config, account: account, key: :plan, value: true)
          template = create(:template, account: account, author: user)
          response = double(status: 500)
          result = described_class.should_retry?(response: response, attempt: 1, record: template)
          expect(result).to be true
        end

        it 'does not retry if account has no plan' do
          template = create(:template, account: account, author: user)
          response = double(status: 500)
          result = described_class.should_retry?(response: response, attempt: 1, record: template)
          expect(result).to be false
        end
      end

      context 'with partnership templates' do
        let(:partnership) { create(:partnership) }
        let(:partnership_template) { create(:template, partnership: partnership, account: nil, author: user) }

        it 'always retries for partnership templates' do
          response = double(status: 500)
          result = described_class.should_retry?(response: response, attempt: 1, record: partnership_template)
          expect(result).to be true
        end
      end

      context 'with submissions' do
        it 'retries if account has plan' do
          create(:account_config, account: account, key: :plan, value: true)
          template = create(:template, account: account, author: user)
          submission = create(:submission, template: template, account: account)
          response = double(status: 500)
          result = described_class.should_retry?(response: response, attempt: 1, record: submission)
          expect(result).to be true
        end

        it 'does not retry if account has no plan' do
          template = create(:template, account: account, author: user)
          submission = create(:submission, template: template, account: account)
          response = double(status: 500)
          result = described_class.should_retry?(response: response, attempt: 1, record: submission)
          expect(result).to be false
        end
      end

      context 'with submitters' do
        it 'retries if account has plan' do
          create(:account_config, account: account, key: :plan, value: true)
          template = create(:template, account: account, author: user)
          submission = create(:submission, template: template, account: account)
          submitter = submission.submitters.create!(uuid: SecureRandom.uuid, email: 'test@example.com', account: account)
          response = double(status: 500)
          result = described_class.should_retry?(response: response, attempt: 1, record: submitter)
          expect(result).to be true
        end

        it 'does not retry if account has no plan' do
          template = create(:template, account: account, author: user)
          submission = create(:submission, template: template, account: account)
          submitter = submission.submitters.create!(uuid: SecureRandom.uuid, email: 'test@example.com', account: account)
          response = double(status: 500)
          result = described_class.should_retry?(response: response, attempt: 1, record: submitter)
          expect(result).to be false
        end
      end
    end
  end

  describe '.eligible_for_retries?' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    context 'with Template' do
      it 'returns true if account has plan' do
        create(:account_config, account: account, key: :plan, value: true)
        template = create(:template, account: account, author: user)
        expect(described_class.eligible_for_retries?(template)).to be true
      end

      it 'returns false if account has no plan' do
        template = create(:template, account: account, author: user)
        expect(described_class.eligible_for_retries?(template)).to be false
      end

      it 'returns true for partnership templates' do
        partnership = create(:partnership)
        template = create(:template, partnership: partnership, account: nil, author: user)
        expect(described_class.eligible_for_retries?(template)).to be true
      end
    end

    context 'with Submission' do
      it 'returns true if account has plan' do
        create(:account_config, account: account, key: :plan, value: true)
        template = create(:template, account: account, author: user)
        submission = create(:submission, template: template, account: account)
        expect(described_class.eligible_for_retries?(submission)).to be true
      end

      it 'returns false if account has no plan' do
        template = create(:template, account: account, author: user)
        submission = create(:submission, template: template, account: account)
        expect(described_class.eligible_for_retries?(submission)).to be false
      end
    end

    context 'with Submitter' do
      it 'returns true if account has plan' do
        create(:account_config, account: account, key: :plan, value: true)
        template = create(:template, account: account, author: user)
        submission = create(:submission, template: template, account: account)
        submitter = submission.submitters.create!(uuid: SecureRandom.uuid, email: 'test@example.com', account: account)
        expect(described_class.eligible_for_retries?(submitter)).to be true
      end

      it 'returns false if account has no plan' do
        template = create(:template, account: account, author: user)
        submission = create(:submission, template: template, account: account)
        submitter = submission.submitters.create!(uuid: SecureRandom.uuid, email: 'test@example.com', account: account)
        expect(described_class.eligible_for_retries?(submitter)).to be false
      end
    end

    context 'with unknown record type' do
      it 'returns false' do
        unknown_record = Object.new
        expect(described_class.eligible_for_retries?(unknown_record)).to be false
      end
    end
  end
end
