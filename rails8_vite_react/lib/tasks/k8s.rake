namespace :k8s do
  desc "Deploy user app for specific user"
  task :deploy_user_app, [:user_id] => :environment do |t, args|
    user_id = args[:user_id]
    raise "User ID is required" unless user_id

    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    puts "Deploying app for user #{user_id}..."
    result = service.deploy_user_app
    puts "Successfully deployed: #{result[:url]}"
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end

  desc "Undeploy user app for specific user"
  task :undeploy_user_app, [:user_id] => :environment do |t, args|
    user_id = args[:user_id]
    raise "User ID is required" unless user_id

    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    puts "Undeploying app for user #{user_id}..."
    service.undeploy_user_app
    puts "Successfully undeployed"
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end

  desc "Start user app"
  task :start_user_app, [:user_id] => :environment do |t, args|
    user_id = args[:user_id]
    raise "User ID is required" unless user_id

    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    puts "Starting app for user #{user_id}..."
    service.start_user_app
    puts "Successfully started"
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end

  desc "Stop user app"
  task :stop_user_app, [:user_id] => :environment do |t, args|
    user_id = args[:user_id]
    raise "User ID is required" unless user_id

    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    puts "Stopping app for user #{user_id}..."
    service.stop_user_app
    puts "Successfully stopped"
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end

  desc "Check status of user app"
  task :status, [:user_id] => :environment do |t, args|
    user_id = args[:user_id]
    raise "User ID is required" unless user_id

    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    status = service.app_status
    puts "User #{user_id} app status: #{status}"
    
    if user.app_url.present?
      puts "App URL: #{user.app_url}"
    end
  end

  desc "List all user apps"
  task :list_all => :environment do
    service = K8s::MaintenanceService.new
    apps = service.list_all_user_apps
    
    puts "All User Apps:"
    puts "=" * 80
    printf "%-10s %-20s %-30s %-15s %s\n", "UserID", "Namespace", "Release", "Status", "Updated"
    puts "-" * 80
    
    apps.each do |app|
      printf "%-10s %-20s %-30s %-15s %s\n", 
             app[:user_id], 
             app[:namespace], 
             app[:release_name], 
             app[:status], 
             app[:updated]
    end
  end

  desc "Cleanup orphaned resources"
  task :cleanup => :environment do
    service = K8s::MaintenanceService.new
    puts "Cleaning up orphaned resources..."
    
    orphaned = service.cleanup_orphaned_resources
    puts "Cleaned up #{orphaned.length} orphaned namespaces:"
    orphaned.each { |ns| puts "  - #{ns}" }
  end

  desc "Get cluster resources overview"
  task :cluster_info => :environment do
    service = K8s::MaintenanceService.new
    resources = service.get_cluster_resources
    
    puts "Cluster Overview:"
    puts "=" * 50
    puts "Nodes: #{resources[:nodes].length}"
    puts "Total Pods: #{resources[:pods]}"
    puts "User Apps: #{resources[:user_apps]}"
    puts
    
    puts "Nodes Details:"
    resources[:nodes].each do |node|
      puts "  #{node[:name]}: #{node[:status]}"
    end
  end
end
