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
