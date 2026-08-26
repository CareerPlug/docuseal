# frozen_string_literal: true

require 'rails_helper'

describe 'Pendo snippet' do
  let(:account) { create(:account, external_account_id: 99) }
  let(:user) { create(:user, account:, external_user_id: 42) }

  around do |example|
    ENV['PENDO_API_KEY'] = 'test-pendo-key'
    example.run
  ensure
    ENV.delete('PENDO_API_KEY')
  end

  def expect_pendo_snippet(body)
    expect(body).to include('cdn.pendo.io/agent/static/')
    expect(body).to include('pendo.initialize')
    expect(body).to include('test-pendo-key')
  end

  it 'is absent when PENDO_API_KEY is blank' do
    ENV.delete('PENDO_API_KEY')
    sign_in(user)
    get root_path
    expect(response.body).not_to include('cdn.pendo.io')
  end

  it 'loads on the application layout with ATS visitor/account ids' do
    sign_in(user)
    get root_path
    expect(response).to have_http_status(:ok)
    expect_pendo_snippet(response.body)
    expect(response.body).to include('"id":42')
    expect(response.body).to include('"id":99')
  end

  it 'loads on the form layout (signing iframe)' do
    template = create(:template, account:, author: user)
    submission = create(:submission, template:, account:, created_by_user: user)
    submitter = create(:submitter, submission:, account:, uuid: template.submitters.first['uuid'])

    get submit_form_path(slug: submitter.slug, auth_token: user.access_token.token)

    expect(response).to have_http_status(:ok)
    expect_pendo_snippet(response.body)
    expect(response.body).to include('"id":42')
  end

  it 'loads on the plain layout (template editor iframe)' do
    template = create(:template, account:, author: user)
    sign_in(user)
    get edit_template_path(template)
    expect(response).to have_http_status(:ok)
    expect_pendo_snippet(response.body)
  end

  it 'does not crash for a signed-in partnership user with no account' do
    partner_user = create(:user, :with_partnership, external_user_id: 7)
    template = create(:template, account:, author: user)
    submission = create(:submission, template:, account:, created_by_user: user)
    submitter = create(:submitter, submission:, account:, uuid: template.submitters.first['uuid'])

    get submit_form_path(slug: submitter.slug, auth_token: partner_user.access_token.token)

    expect(response).to have_http_status(:ok)
    expect_pendo_snippet(response.body)
    expect(response.body).to include('"id":7')
    expect(response.body).not_to include('"account"')
  end
end
