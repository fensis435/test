# app/services/k8s/base_service.rb
class K8s::BaseService
  class K8sError < StandardError; end
  
  private

  def k8s_client
    @k8s_client ||= Kubeclient::Client.new(
      Rails.application.config.k8s_api_endpoint,
      'v1',
      auth_options: k8s_auth_options,
      ssl_options: k8s_ssl_options
    )
  end

  def k8s_apps_client
    @k8s_apps_client ||= Kubeclient::Client.new(
      Rails.application.config.k8s_api_endpoint,
      'apps/v1',
      auth_options: k8s_auth_options,
      ssl_options: k8s_ssl_options
    )
  end

  def k8s_networking_client
    @k8s_networking_client ||= Kubeclient::Client.new(
      Rails.application.config.k8s_api_endpoint,
      'networking.k8s.io/v1',
      auth_options: k8s_auth_options,
      ssl_options: k8s_ssl_options
    )
  end

  def helm_command(command)
    result = `#{command} 2>&1`
    raise K8sError, result unless $?.success?
    result
  end

  def generate_namespace(user_id)
    "user-#{user_id}-#{SecureRandom.hex(4)}"
  end

  def k8s_auth_options
    if Rails.application.config.k8s_token.present?
      { bearer_token: Rails.application.config.k8s_token }
    elsif Rails.application.config.k8s_username.present?
      {
        username: Rails.application.config.k8s_username,
        password: Rails.application.config.k8s_password
      }
    else
      {} # Use kubeconfig default
    end
  end

  def k8s_ssl_options
    if Rails.application.config.k8s_verify_ssl == false
      { verify_ssl: OpenSSL::SSL::VERIFY_NONE }
    else
      {}
    end
  end

  def handle_k8s_error(&block)
    yield
  rescue Kubeclient::HttpError => e
    Rails.logger.error "Kubernetes API error: #{e.message}"
    raise K8sError, e.message
  rescue => e
    Rails.logger.error "Kubernetes operation error: #{e.message}"
    raise K8sError, e.message
  end
end

# app/services/k8s/namespace_service.rb
class K8s::NamespaceService < K8s::BaseService
  def create(namespace)
    handle_k8s_error do
      ns = Kubeclient::Resource.new(
        metadata: {
          name: namespace,
          labels: {
            'managed-by' => 'rails-k8s-controller',
            'user-namespace' => 'true'
          }
        }
      )
      k8s_client.create_namespace(ns)
      Rails.logger.info "Created namespace: #{namespace}"
    end
  end

  def delete(namespace)
    handle_k8s_error do
      k8s_client.delete_namespace(namespace)
      Rails.logger.info "Deleted namespace: #{namespace}"
    end
  end

  def exists?(namespace)
    handle_k8s_error do
      k8s_client.get_namespace(namespace)
      true
    end
  rescue K8sError
    false
  end

  def list_user_namespaces(user_id)
    handle_k8s_error do
      namespaces = k8s_client.get_namespaces(
        label_selector: 'user-namespace=true'
      )
      
      namespaces.select { |ns| ns.metadata.name.start_with?("user-#{user_id}-") }
                .map { |ns| ns.metadata.name }
    end
  end

  def get(namespace)
    handle_k8s_error do
      k8s_client.get_namespace(namespace)
    end
  end
end

# app/services/k8s/helm_service.rb
class K8s::HelmService < K8s::BaseService
  def initialize(chart_path: nil, chart_name: nil, values_file: nil)
    @chart_path = chart_path || Rails.application.config.helm_chart_path
    @chart_name = chart_name || Rails.application.config.helm_chart_name
    @values_file = values_file || Rails.application.config.helm_values_file
  end

  def install(release_name:, namespace:, values: {})
    values_args = build_values_args(values)
    
    command = [
      "helm install #{release_name}",
      @chart_path,
      "--namespace #{namespace}",
      "--create-namespace",
      values_args,
      @values_file ? "--values #{@values_file}" : nil
    ].compact.join(' ')
    
    helm_command(command)
    Rails.logger.info "Installed helm release: #{release_name} in namespace: #{namespace}"
  end

  def uninstall(release_name:, namespace:)
    helm_command("helm uninstall #{release_name} --namespace #{namespace}")
    Rails.logger.info "Uninstalled helm release: #{release_name} from namespace: #{namespace}"
  end

  def upgrade(release_name:, namespace:, values: {})
    values_args = build_values_args(values)
    
    command = [
      "helm upgrade #{release_name}",
      @chart_path,
      "--namespace #{namespace}",
      values_args,
      @values_file ? "--values #{@values_file}" : nil
    ].compact.join(' ')
    
    helm_command(command)
    Rails.logger.info "Upgraded helm release: #{release_name} in namespace: #{namespace}"
  end

  def status(release_name:, namespace:)
    result = helm_command("helm status #{release_name} --namespace #{namespace} -o json")
    JSON.parse(result)
  end

  def list(namespace: nil)
    command = namespace ? "helm list --namespace #{namespace} -o json" : "helm list --all-namespaces -o json"
    result = helm_command(command)
    JSON.parse(result)
  end

  def release_exists?(release_name:, namespace:)
    result = `helm status #{release_name} --namespace #{namespace} 2>/dev/null`
    $?.success?
  end

  private

  def build_values_args(values)
    return '' if values.empty?
    
    values.map { |key, value| "--set #{key}=#{value}" }.join(' ')
  end
end

# app/services/k8s/deployment_service.rb
class K8s::DeploymentService < K8s::BaseService
  def scale(deployment_name:, namespace:, replicas:)
    handle_k8s_error do
      deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
      deployment.spec.replicas = replicas
      k8s_apps_client.update_deployment(deployment)
      Rails.logger.info "Scaled deployment #{deployment_name} to #{replicas} replicas in namespace: #{namespace}"
    end
  end

  def restart(deployment_name:, namespace:)
    handle_k8s_error do
      deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
      
      # Add restart annotation to trigger rolling restart
      deployment.spec.template.metadata.annotations ||= {}
      deployment.spec.template.metadata.annotations['kubectl.kubernetes.io/restartedAt'] = Time.current.iso8601
      
      k8s_apps_client.update_deployment(deployment)
      Rails.logger.info "Restarted deployment: #{deployment_name} in namespace: #{namespace}"
    end
  end

  def status(deployment_name:, namespace:)
    handle_k8s_error do
      deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
      {
        'metadata' => {
          'name' => deployment.metadata.name,
          'namespace' => deployment.metadata.namespace
        },
        'status' => {
          'replicas' => deployment.status.replicas,
          'readyReplicas' => deployment.status.readyReplicas,
          'unavailableReplicas' => deployment.status.unavailableReplicas,
          'conditions' => deployment.status.conditions&.map(&:to_h)
        }
      }
    end
  end

  def wait_for_rollout(deployment_name:, namespace:, timeout: 300)
    handle_k8s_error do
      start_time = Time.current
      
      loop do
        deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
        
        desired_replicas = deployment.spec.replicas || 0
        ready_replicas = deployment.status.readyReplicas || 0
        
        break if ready_replicas >= desired_replicas
        
        if Time.current - start_time > timeout
          raise K8sError, "Timeout waiting for deployment #{deployment_name} rollout"
        end
        
        sleep 5
      end
      
      Rails.logger.info "Deployment #{deployment_name} rollout completed in namespace: #{namespace}"
    end
  end

  def get_pods(deployment_name:, namespace:)
    handle_k8s_error do
      pods = k8s_client.get_pods(
        namespace: namespace,
        label_selector: "app=#{deployment_name}"
      )
      
      {
        'items' => pods.map do |pod|
          {
            'metadata' => {
              'name' => pod.metadata.name,
              'namespace' => pod.metadata.namespace
            },
            'status' => {
              'phase' => pod.status.phase,
              'conditions' => pod.status.conditions&.map(&:to_h)
            }
          }
        end
      }
    end
  end

  def exists?(deployment_name:, namespace:)
    handle_k8s_error do
      k8s_apps_client.get_deployment(deployment_name, namespace)
      true
    end
  rescue K8sError
    false
  end
end

# app/services/k8s/ingress_service.rb
class K8s::IngressService < K8s::BaseService
  def create_ingress(name:, namespace:, host:, service_name:, service_port:, tls: true)
    handle_k8s_error do
      ingress = build_ingress_resource(
        name: name,
        namespace: namespace,
        host: host,
        service_name: service_name,
        service_port: service_port,
        tls: tls
      )
      
      k8s_networking_client.create_ingress(ingress)
      Rails.logger.info "Created ingress: #{name} for host: #{host} in namespace: #{namespace}"
    end
  end

  def delete_ingress(name:, namespace:)
    handle_k8s_error do
      k8s_networking_client.delete_ingress(name, namespace)
      Rails.logger.info "Deleted ingress: #{name} in namespace: #{namespace}"
    end
  end

  def get_ingress(name:, namespace:)
    handle_k8s_error do
      ingress = k8s_networking_client.get_ingress(name, namespace)
      {
        'metadata' => {
          'name' => ingress.metadata.name,
          'namespace' => ingress.metadata.namespace
        },
        'spec' => ingress.spec.to_h,
        'status' => ingress.status&.to_h
      }
    end
  end

  def exists?(name:, namespace:)
    handle_k8s_error do
      k8s_networking_client.get_ingress(name, namespace)
      true
    end
  rescue K8sError
    false
  end

  private

  def build_ingress_resource(name:, namespace:, host:, service_name:, service_port:, tls:)
    ingress_spec = {
      rules: [{
        host: host,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: service_name,
                port: {
                  number: service_port
                }
              }
            }
          }]
        }
      }]
    }

    if tls
      ingress_spec[:tls] = [{
        hosts: [host],
        secretName: "#{name}-tls"
      }]
    end

    Kubeclient::Resource.new(
      metadata: {
        name: name,
        namespace: namespace,
        annotations: {
          'kubernetes.io/ingress.class' => 'nginx',
          'nginx.ingress.kubernetes.io/rewrite-target' => '/$1'
        }
      },
      spec: ingress_spec
    )
  end
end

# app/services/k8s/user_app_service.rb
class K8s::UserAppService < K8s::BaseService
  def initialize(user)
    @user = user
    @namespace_service = K8s::NamespaceService.new
    @helm_service = K8s::HelmService.new
    @deployment_service = K8s::DeploymentService.new
    @ingress_service = K8s::IngressService.new
  end

  def deploy_user_app(force_recreate: false)
    namespace = find_or_create_namespace
    release_name = generate_release_name
    
    if force_recreate && @helm_service.release_exists?(release_name: release_name, namespace: namespace)
      undeploy_user_app
      namespace = find_or_create_namespace
    end

    values = build_helm_values
    
    @helm_service.install(
      release_name: release_name,
      namespace: namespace,
      values: values
    )

    # Wait for deployment to be ready
    @deployment_service.wait_for_rollout(
      deployment_name: release_name,
      namespace: namespace
    )

    # Create ingress
    create_user_ingress(release_name, namespace)

    # Update user record
    update_user_app_info(namespace, release_name)

    {
      namespace: namespace,
      release_name: release_name,
      url: generate_app_url
    }
  end

  def undeploy_user_app
    return unless @user.k8s_namespace.present?

    release_name = @user.k8s_release_name || generate_release_name
    
    # Delete helm release
    if @helm_service.release_exists?(release_name: release_name, namespace: @user.k8s_namespace)
      @helm_service.uninstall(release_name: release_name, namespace: @user.k8s_namespace)
    end

    # Delete namespace
    if @namespace_service.exists?(@user.k8s_namespace)
      @namespace_service.delete(@user.k8s_namespace)
    end

    # Update user record
    @user.update!(
      k8s_namespace: nil,
      k8s_release_name: nil,
      app_url: nil,
      app_status: 'stopped'
    )
  end

  def start_user_app
    return deploy_user_app unless app_deployed?

    @deployment_service.scale(
      deployment_name: @user.k8s_release_name,
      namespace: @user.k8s_namespace,
      replicas: 1
    )

    @user.update!(app_status: 'running')
  end

  def stop_user_app
    return unless app_deployed?

    @deployment_service.scale(
      deployment_name: @user.k8s_release_name,
      namespace: @user.k8s_namespace,
      replicas: 0
    )

    @user.update!(app_status: 'stopped')
  end

  def restart_user_app
    return unless app_deployed?

    @deployment_service.restart(
      deployment_name: @user.k8s_release_name,
      namespace: @user.k8s_namespace
    )

    @user.update!(app_status: 'running')
  end

  def app_status
    return 'not_deployed' unless app_deployed?

    begin
      status = @deployment_service.status(
        deployment_name: @user.k8s_release_name,
        namespace: @user.k8s_namespace
      )
      
      replicas = status.dig('status', 'replicas') || 0
      ready_replicas = status.dig('status', 'readyReplicas') || 0
      
      if replicas == 0
        'stopped'
      elsif ready_replicas == replicas
        'running'
      else
        'starting'
      end
    rescue K8sError
      'error'
    end
  end

  def app_logs(lines: 100)
    return [] unless app_deployed?

    begin
      pods = @deployment_service.get_pods(
        deployment_name: @user.k8s_release_name,
        namespace: @user.k8s_namespace
      )
      
      all_logs = []
      
      pods['items'].each do |pod|
        pod_name = pod['metadata']['name']
        
        begin
          pod_logs = k8s_client.get_pod_log(
            pod_name,
            @user.k8s_namespace,
            tail_lines: lines,
            timestamps: true
          )
          
          pod_logs.split("\n").each do |line|
            all_logs << "[#{pod_name}] #{line}"
          end
        rescue => e
          Rails.logger.warn "Failed to get logs from pod #{pod_name}: #{e.message}"
        end
      end
      
      all_logs.last(lines)
    rescue K8sError => e
      Rails.logger.error "Failed to get logs: #{e.message}"
      []
    end
  end

  private

  def find_or_create_namespace
    existing_namespaces = @namespace_service.list_user_namespaces(@user.id)
    
    if existing_namespaces.any?
      existing_namespaces.first
    else
      namespace = generate_namespace(@user.id)
      @namespace_service.create(namespace)
      namespace
    end
  end

  def generate_release_name
    "user-app-#{@user.id}"
  end

  def build_helm_values
    {
      'image.tag' => Rails.application.config.app_image_tag || 'latest',
      'ingress.enabled' => 'false', # We create ingress separately
      'service.port' => '80',
      'resources.requests.memory' => '256Mi',
      'resources.requests.cpu' => '100m',
      'resources.limits.memory' => '512Mi',
      'resources.limits.cpu' => '500m'
    }
  end

  def create_user_ingress(release_name, namespace)
    host = generate_host_name
    
    @ingress_service.create_ingress(
      name: "#{release_name}-ingress",
      namespace: namespace,
      host: host,
      service_name: release_name,
      service_port: 80
    )
  end

  def generate_host_name
    base_domain = Rails.application.config.app_base_domain
    "user-#{@user.id}.#{base_domain}"
  end

  def generate_app_url
    protocol = Rails.env.production? ? 'https' : 'http'
    "#{protocol}://#{generate_host_name}"
  end

  def update_user_app_info(namespace, release_name)
    @user.update!(
      k8s_namespace: namespace,
      k8s_release_name: release_name,
      app_url: generate_app_url,
      app_status: 'running'
    )
  end

  def app_deployed?
    @user.k8s_namespace.present? && @user.k8s_release_name.present?
  end
end

# app/services/k8s/maintenance_service.rb
class K8s::MaintenanceService < K8s::BaseService
  def initialize
    @namespace_service = K8s::NamespaceService.new
    @helm_service = K8s::HelmService.new
  end

  def list_all_user_apps
    releases = @helm_service.list
    
    releases.map do |release|
      namespace = release['namespace']
      name = release['name']
      status = release['status']
      
      user_id = extract_user_id_from_release_name(name)
      
      {
        user_id: user_id,
        namespace: namespace,
        release_name: name,
        status: status,
        chart_version: release['chart'],
        updated: release['updated']
      }
    end
  end

  def cleanup_orphaned_resources
    # Find namespaces that don't have corresponding users
    handle_k8s_error do
      all_namespaces = k8s_client.get_namespaces(
        label_selector: 'user-namespace=true'
      )
      
      orphaned = []

      all_namespaces.each do |namespace|
        namespace_name = namespace.metadata.name
        user_id = extract_user_id_from_namespace(namespace_name)
        
        unless User.exists?(user_id)
          orphaned << namespace_name
          Rails.logger.warn "Found orphaned namespace: #{namespace_name} for non-existent user: #{user_id}"
        end
      end

      orphaned.each do |namespace_name|
        begin
          @namespace_service.delete(namespace_name)
          Rails.logger.info "Cleaned up orphaned namespace: #{namespace_name}"
        rescue K8sError => e
          Rails.logger.error "Failed to clean up namespace #{namespace_name}: #{e.message}"
        end
      end

      orphaned
    end
  end

  def force_deploy_user_app(user_id)
    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    service.deploy_user_app(force_recreate: true)
  end

  def force_undeploy_user_app(user_id)
    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    service.undeploy_user_app
  end

  def get_cluster_resources
    handle_k8s_error do
      nodes = k8s_client.get_nodes
      all_pods = k8s_client.get_pods
      
      user_namespaces = k8s_client.get_namespaces(
        label_selector: 'user-namespace=true'
      )
      
      {
        nodes: nodes.map do |node|
          {
            name: node.metadata.name,
            status: node.status.conditions&.last&.type || 'Unknown',
            capacity: node.status.capacity&.to_h || {},
            allocatable: node.status.allocatable&.to_h || {}
          }
        end,
        pods: all_pods.length,
        user_apps: user_namespaces.length
      }
    end
  end

  private

  def extract_user_id_from_release_name(release_name)
    match = release_name.match(/^user-app-(\d+)$/)
    match ? match[1].to_i : nil
  end

  def extract_user_id_from_namespace(namespace)
    match = namespace.match(/^user-(\d+)-/)
    match ? match[1].to_i : nil
  end
end