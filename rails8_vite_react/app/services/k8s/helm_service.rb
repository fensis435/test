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
