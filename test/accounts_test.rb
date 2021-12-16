require File.expand_path(File.dirname(__FILE__) + '/test_config.rb')

class CoreTest < ActiveSupport::TestCase
  include Capybara::DSL

  setup do
    Capybara.reset_sessions!
    Dir[Padrino.root('models', '*')].each { |f| f.split('/').last.split('.').first.camelize.constantize.delete_all }
  end

  teardown do
    save_screenshot unless ENV['CI']
  end

  test 'signing up' do
    @account = FactoryBot.build_stubbed(:account)
    visit '/accounts/new'
    fill_in 'Name', with: @account.name
    fill_in 'Email', with: @account.email
    fill_in 'Password', with: @account.password
    fill_in 'Location', with: @account.location
    click_button 'Sign up'
    assert page.has_content? 'Your account was created successfully'
  end

  test 'signing in' do
    @account = FactoryBot.create(:account)
    visit '/accounts/sign_in'
    fill_in 'Email', with: @account.email
    fill_in 'Password', with: @account.password
    click_button 'Sign in'
    assert page.has_content? 'Signed in'
  end

  test 'editing profile' do
    @account = FactoryBot.create(:account)
    login_as(@account)
    click_link @account.name
    click_link 'Edit profile'
    fill_in 'Name', with: (name = FactoryBot.build_stubbed(:account).name)
    click_button 'Save profile'
    assert page.has_content? 'Your account was updated successfully'
    assert page.has_content? name
  end
end
