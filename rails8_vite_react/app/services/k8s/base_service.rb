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

