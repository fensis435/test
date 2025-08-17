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

