# Kubernetes設定の初期化
Rails.application.configure do
  # kubectlとhelmコマンドのパスを確認
  config.after_initialize do
    begin
      kubectl_version = `kubectl version --client --short 2>/dev/null`
      helm_version = `helm version --short 2>/dev/null`
      
      Rails.logger.info "Kubernetes tools detected:"
      Rails.logger.info "kubectl: #{kubectl_version.strip}" if $?.success?
      Rails.logger.info "helm: #{helm_version.strip}" if $?.success?
      
      # 設定値の検証
      required_configs = %w[helm_chart_path app_base_domain]
      missing_configs = required_configs.select { |config| Rails.application.config.send(config).blank? }
      
      if missing_configs.any?
        Rails.logger.warn "Missing required Kubernetes configurations: #{missing_configs.join(', ')}"
      end
      
    rescue => e
      Rails.logger.error "Failed to initialize Kubernetes configuration: #{e.message}"
    end
  end
end
