# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Submitters::SubmitValues do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) { create(:template, account: account) }
  let(:submission) { create(:submission, template: template, account: account) }
  let(:submitter) { create(:submitter, submission: submission, account: account, uuid: SecureRandom.uuid) }
  let(:request) { instance_double(ActionDispatch::Request, remote_ip: '127.0.0.1', user_agent: 'TestAgent') }

  before do
    allow(request).to receive_messages(
      session: instance_double(ActionDispatch::Request::Session, id: 'session_id'),
      env: { 'warden' => instance_double(Warden::Proxy, user: user) }
    )

    # Setup template fields
    fields = [
      { 'uuid' => 'field_1', 'name' => 'First Name', 'type' => 'text', 'submitter_uuid' => submitter.uuid },
      { 'uuid' => 'field_2', 'name' => 'Last Name', 'type' => 'text', 'submitter_uuid' => submitter.uuid }
    ]
    template.update!(fields: fields)
    submission.update!(template_fields: fields)

    # Initialize submitter values
    submitter.update!(values: { 'field_1' => 'John', 'field_2' => 'Doe' })
    create(:submission_event, submission: submission, submitter: submitter, event_type: 'start_form')
  end

  describe '.call' do
    context 'when values change' do
      let(:params) do
        {
          values: { 'field_1' => 'Jane' }
        }
      end

      it 'creates a form_update event with changes' do
        expect do
          described_class.call(submitter, ActionController::Parameters.new(params), request, user)
        end.to change(SubmissionEvent, :count).by(1)

        event = SubmissionEvent.last
        expect(event.event_type).to eq('form_update')
        expect(event.user).to eq(user)
        expect(event.data['changes']).to include(
          hash_including('field' => 'First Name', 'from' => 'John', 'to' => 'Jane')
        )
      end
    end

    context 'when values do not change' do
      let(:params) do
        {
          values: { 'field_1' => 'John' }
        }
      end

      it 'does not create a form_update event' do
        expect do
          described_class.call(submitter, ActionController::Parameters.new(params), request, user)
        end.not_to change(SubmissionEvent, :count)
      end
    end

    context 'when multiple fields change' do
      let(:params) do
        {
          values: { 'field_1' => 'Jane', 'field_2' => 'Smith' }
        }
      end

      it 'records all changes' do
        described_class.call(submitter, ActionController::Parameters.new(params), request, user)

        event = SubmissionEvent.last
        changes = event.data['changes']

        expect(changes.size).to eq(2)
        expect(changes).to include(hash_including('field' => 'First Name', 'to' => 'Jane'))
        expect(changes).to include(hash_including('field' => 'Last Name', 'to' => 'Smith'))
      end
    end
  end
end
