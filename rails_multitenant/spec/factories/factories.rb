FactoryBot.define do
  factory :tenant_record do
    sequence(:slug) { |n| "tenant-#{n}" }
    sequence(:name) { |n| "Tenant #{n}" }
    status { "active" }
    plan { "professional" }
    settings do
      {
        "max_users" => 100,
        "storage_gb" => 100,
        "api_rate_limit" => 2000,
        "mfa_required" => false
      }
    end
    database_config do
      {
        "host" => "localhost",
        "port" => 5432,
        "database" => "tenant_#{slug.gsub("-", "_")}",
        "username" => "tenant_user",
        "schema" => "public",
        "platform" => "aws",
        "endpoint_type" => "rds",
        "ssl_mode" => "require",
        "pool_size" => 5
      }
    end

    trait :provisioning do
      status { "provisioning" }
      database_config { nil }
    end

    trait :suspended do
      status { "suspended" }
      suspended_at { 1.day.ago }
    end

    trait :terminated do
      status { "terminated" }
    end

    trait :free_plan do
      plan { "free" }
      settings do
        { "max_users" => 5, "storage_gb" => 1, "api_rate_limit" => 100 }
      end
    end

    trait :enterprise do
      plan { "enterprise" }
      settings do
        { "max_users" => nil, "storage_gb" => nil, "api_rate_limit" => 10_000, "sso_enabled" => true }
      end
    end

    trait :onprem do
      database_config do
        {
          "host" => "postgres-#{slug}.default.svc.cluster.local",
          "port" => 5432,
          "database" => "tenant_#{slug.gsub("-", "_")}",
          "username" => "tenant_user",
          "schema" => "public",
          "platform" => "onprem",
          "endpoint_type" => "pod",
          "ssl_mode" => "disable",
          "pool_size" => 5
        }
      end
    end
  end

  factory :user_record do
    sequence(:cognito_sub) { |n| "cognito-sub-#{n}-#{SecureRandom.hex(4)}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:display_name) { |n| "User #{n}" }
    role { "member" }
    deactivated_at { nil }

    trait :admin do
      role { "admin" }
    end

    trait :owner do
      role { "owner" }
    end

    trait :viewer do
      role { "viewer" }
    end

    trait :deactivated do
      deactivated_at { 1.day.ago }
    end
  end

  factory :audit_log do
    sequence(:tenant_id) { |_| SecureRandom.uuid }
    sequence(:actor_sub) { |n| "cognito-sub-#{n}" }
    sequence(:actor_email) { |n| "actor#{n}@example.com" }
    actor_role { "admin" }
    action { "user.created" }
    resource_type { "User" }
    sequence(:resource_id) { |_| SecureRandom.uuid }
    metadata { {} }
    occurred_at { Time.current }
  end
end
