# 使用例
class ApplicationController < ActionController::Base
  def deploy_application
    helm = HelmService.new(namespace: 'production', timeout: 600)

    begin
      # 1. リポジトリの追加
      helm.add_repository('bitnami', 'https://charts.bitnami.com/bitnami')
      
      # プライベートリポジトリの場合
      helm.add_repository(
        'private-repo',
        'https://private.example.com/charts',
        username: ENV['HELM_PRIVATE_REPO_USER'],
        password: ENV['HELM_PRIVATE_REPO_PASSWORD']
      )

      # 2. リポジトリの更新
      helm.update_repositories

      # 3. チャートの検索
      search_results = helm.search_charts('nginx')
      puts search_results

      # 4. アプリケーションのインストール
      values = {
        'replicaCount' => 3,
        'image.tag' => 'latest',
        'service.type' => 'LoadBalancer'
      }

      helm.install(
        'my-nginx',
        'bitnami/nginx',
        values: values,
        version: '13.2.23'
      )

      # 5. インストール状況の確認
      status = helm.get_release_status('my-nginx')
      puts "Release status: #{status['info']['status']}"

      # 6. アプリケーションのアップグレード
      new_values = values.merge('replicaCount' => 5)
      helm.upgrade('my-nginx', 'bitnami/nginx', values: new_values)

      render json: { status: 'success', message: 'Application deployed successfully' }

    rescue HelmService::ChartNotFoundError => e
      render json: { status: 'error', message: "Chart not found: #{e.message}" }, status: 404
    rescue HelmService::ReleaseNotFoundError => e
      render json: { status: 'error', message: "Release not found: #{e.message}" }, status: 404
    rescue HelmService::CommandExecutionError => e
      render json: { status: 'error', message: "Helm command failed: #{e.message}" }, status: 500
    rescue HelmService::HelmError => e
      render json: { status: 'error', message: "Helm error: #{e.message}" }, status: 500
    end
  end

  def list_deployments
    helm = HelmService.new(namespace: params[:namespace] || 'default')
    
    begin
      releases = helm.list_releases
      render json: { releases: releases }
    rescue HelmService::HelmError => e
      render json: { status: 'error', message: e.message }, status: 500
    end
  end

  def rollback_deployment
    helm = HelmService.new(namespace: params[:namespace] || 'default')
    
    begin
      # リリース履歴の取得
      history = helm.get_release_history(params[:release_name])
      
      # 前のバージョンにロールバック
      if history.length > 1
        previous_revision = history[-2]['revision']
        helm.rollback(params[:release_name], previous_revision)
        render json: { status: 'success', message: "Rolled back to revision #{previous_revision}" }
      else
        render json: { status: 'error', message: 'No previous revision to rollback to' }, status: 400
      end
    rescue HelmService::ReleaseNotFoundError => e
      render json: { status: 'error', message: e.message }, status: 404
    rescue HelmService::HelmError => e
      render json: { status: 'error', message: e.message }, status: 500
    end
  end
end

# Job での使用例
class HelmDeploymentJob < ApplicationJob
  queue_as :default

  def perform(chart_name, release_name, namespace, values = {})
    helm = HelmService.new(namespace: namespace)

    begin
      # ドライラン実行
      dry_run_result = helm.dry_run(release_name, chart_name, values: values)
      Rails.logger.info "Dry run successful: #{dry_run_result}"

      # 実際のデプロイメント
      helm.install(release_name, chart_name, values: values)
      
      # デプロイメント確認
      status = helm.get_release_status(release_name)
      if status['info']['status'] == 'deployed'
        Rails.logger.info "Successfully deployed #{release_name}"
      else
        Rails.logger.error "Deployment failed with status: #{status['info']['status']}"
      end

    rescue HelmService::HelmError => e
      Rails.logger.error "Helm deployment failed: #{e.message}"
      raise e
    end
  end
end

# カスタム設定クラスの例
class HelmConfiguration
  def self.for_environment(env)
    case env
    when 'development'
      {
        namespace: 'dev',
        timeout: 300,
        repositories: {
          'stable' => 'https://charts.helm.sh/stable',
          'bitnami' => 'https://charts.bitnami.com/bitnami'
        }
      }
    when 'staging'
      {
        namespace: 'staging',
        timeout: 600,
        repositories: {
          'stable' => 'https://charts.helm.sh/stable',
          'bitnami' => 'https://charts.bitnami.com/bitnami',
          'private' => ENV['STAGING_HELM_REPO']
        }
      }
    when 'production'
      {
        namespace: 'production',
        timeout: 900,
        repositories: {
          'stable' => 'https://charts.helm.sh/stable',
          'bitnami' => 'https://charts.bitnami.com/bitnami',
          'private' => ENV['PRODUCTION_HELM_REPO']
        }
      }
    end
  end
end