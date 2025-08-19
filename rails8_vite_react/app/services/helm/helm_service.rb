# app/services/helm_service.rb
class HelmService
  class HelmError < StandardError; end
  class CommandExecutionError < HelmError; end
  class ChartNotFoundError < HelmError; end
  class ReleaseNotFoundError < HelmError; end

  def initialize(namespace: 'default', timeout: 300)
    @namespace = namespace
    @timeout = timeout
  end

  # リポジトリ操作
  def add_repository(name, url, username: nil, password: nil)
    cmd = build_command('repo', 'add', name, url)
    
    if username && password
      cmd += " --username #{username} --password #{password}"
    end
    
    execute_command(cmd)
  end

  def update_repositories
    execute_command(build_command('repo', 'update'))
  end

  def list_repositories
    result = execute_command(build_command('repo', 'list', '-o', 'json'))
    JSON.parse(result)
  rescue JSON::ParserError => e
    raise HelmError, "Failed to parse repository list: #{e.message}"
  end

  def remove_repository(name)
    execute_command(build_command('repo', 'remove', name))
  end

  # チャート検索
  def search_charts(keyword, repo: nil, max_col_width: 50)
    cmd = build_command('search', 'repo', keyword, '--max-col-width', max_col_width.to_s)
    cmd += " --repo #{repo}" if repo
    
    execute_command(cmd)
  end

  # リリース操作
  def install(release_name, chart, values: {}, values_file: nil, version: nil, create_namespace: true)
    cmd = build_command('install', release_name, chart, '--namespace', @namespace)
    cmd += ' --create-namespace' if create_namespace
    cmd += " --version #{version}" if version
    cmd += " --values #{values_file}" if values_file
    cmd += " --timeout #{@timeout}s"

    # 値の設定
    values.each do |key, value|
      cmd += " --set #{key}=#{value}"
    end

    execute_command(cmd)
  end

  def upgrade(release_name, chart, values: {}, values_file: nil, version: nil, install: true)
    cmd = build_command('upgrade', release_name, chart, '--namespace', @namespace)
    cmd += ' --install' if install
    cmd += " --version #{version}" if version
    cmd += " --values #{values_file}" if values_file
    cmd += " --timeout #{@timeout}s"

    values.each do |key, value|
      cmd += " --set #{key}=#{value}"
    end

    execute_command(cmd)
  end

  def uninstall(release_name, keep_history: false)
    cmd = build_command('uninstall', release_name, '--namespace', @namespace)
    cmd += ' --keep-history' if keep_history
    cmd += " --timeout #{@timeout}s"
    
    execute_command(cmd)
  end

  def rollback(release_name, revision = nil)
    cmd = build_command('rollback', release_name, '--namespace', @namespace)
    cmd += " #{revision}" if revision
    cmd += " --timeout #{@timeout}s"
    
    execute_command(cmd)
  end

  # リリース情報取得
  def list_releases(all_namespaces: false, filter: nil)
    cmd = build_command('list', '--namespace', @namespace, '-o', 'json')
    cmd += ' --all-namespaces' if all_namespaces
    cmd += " --filter '#{filter}'" if filter

    result = execute_command(cmd)
    JSON.parse(result)
  rescue JSON::ParserError => e
    raise HelmError, "Failed to parse releases list: #{e.message}"
  end

  def get_release_status(release_name)
    result = execute_command(build_command('status', release_name, '--namespace', @namespace, '-o', 'json'))
    JSON.parse(result)
  rescue JSON::ParserError => e
    raise HelmError, "Failed to parse release status: #{e.message}"
  end

  def get_release_values(release_name, all: false)
    cmd = build_command('get', 'values', release_name, '--namespace', @namespace, '-o', 'json')
    cmd += ' --all' if all
    
    result = execute_command(cmd)
    JSON.parse(result)
  rescue JSON::ParserError => e
    raise HelmError, "Failed to parse release values: #{e.message}"
  end

  def get_release_manifest(release_name, revision: nil)
    cmd = build_command('get', 'manifest', release_name, '--namespace', @namespace)
    cmd += " --revision #{revision}" if revision
    
    execute_command(cmd)
  end

  def get_release_history(release_name, max: 10)
    result = execute_command(build_command('history', release_name, '--namespace', @namespace, '--max', max.to_s, '-o', 'json'))
    JSON.parse(result)
  rescue JSON::ParserError => e
    raise HelmError, "Failed to parse release history: #{e.message}"
  end

  # テンプレート操作
  def template(release_name, chart, values: {}, values_file: nil, output_dir: nil)
    cmd = build_command('template', release_name, chart, '--namespace', @namespace)
    cmd += " --values #{values_file}" if values_file
    cmd += " --output-dir #{output_dir}" if output_dir

    values.each do |key, value|
      cmd += " --set #{key}=#{value}"
    end

    execute_command(cmd)
  end

  # ドライラン
  def dry_run(release_name, chart, values: {}, values_file: nil)
    cmd = build_command('install', release_name, chart, '--namespace', @namespace, '--dry-run')
    cmd += " --values #{values_file}" if values_file

    values.each do |key, value|
      cmd += " --set #{key}=#{value}"
    end

    execute_command(cmd)
  end

  # バージョン情報
  def version
    result = execute_command(build_command('version', '-o', 'json'))
    JSON.parse(result)
  rescue JSON::ParserError => e
    raise HelmError, "Failed to parse version info: #{e.message}"
  end

  # プラグイン操作
  def install_plugin(plugin_url)
    execute_command(build_command('plugin', 'install', plugin_url))
  end

  def list_plugins
    result = execute_command(build_command('plugin', 'list', '-o', 'json'))
    JSON.parse(result)
  rescue JSON::ParserError => e
    raise HelmError, "Failed to parse plugin list: #{e.message}"
  end

  def uninstall_plugin(plugin_name)
    execute_command(build_command('plugin', 'uninstall', plugin_name))
  end

  private

  def build_command(*args)
    "helm #{args.join(' ')}"
  end

  def execute_command(command)
    Rails.logger.info "Executing Helm command: #{command}"
    
    result = `#{command} 2>&1`
    exit_status = $?.exitstatus

    if exit_status != 0
      error_message = "Helm command failed with exit code #{exit_status}: #{result}"
      Rails.logger.error error_message
      
      case result
      when /not found/
        raise ChartNotFoundError, error_message
      when /release.*not found/
        raise ReleaseNotFoundError, error_message
      else
        raise CommandExecutionError, error_message
      end
    end

    Rails.logger.debug "Helm command result: #{result}"
    result.strip
  end
end