require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
ENV["PLATFORM"] ||= "aws"
ENV["COGNITO_USER_POOL_ID"] ||= "ap-northeast-1_TestPool"
ENV["RDS_HOST"] ||= "localhost"

require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot_rails"
require "shoulda/matchers"
require "database_cleaner/active_record"
require "webmock/rspec"
require "timecop"
require "dry/monads/rspec"

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.fixture_paths = ["#{::Rails.root}/spec/fixtures"]
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include Dry::Monads[:result]

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    TenantResolver::TenantContext.clear
  end

  config.before(:each, :truncation) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
    TenantResolver::TenantContext.clear
  end

  Shoulda::Matchers.configure do |sm_config|
    sm_config.integrate do |with|
      with.test_framework :rspec
      with.library :rails
    end
  end

  WebMock.disable_net_connect!(allow_localhost: true)

  config.include Helpers::AuthHelpers, type: :controller
  config.include Helpers::AuthHelpers, type: :request
  config.include Helpers::TenantHelpers
  config.include Helpers::DatabaseHelpers
end
