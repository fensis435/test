# spec/services/helm_service_spec.rb
require 'rails_helper'

RSpec.describe HelmService do
  let(:service) { described_class.new(namespace: 'test-namespace') }
  let(:mock_command_result) { 'success' }

  before do
    allow(service).to receive(:execute_command).and_return(mock_command_result)
  end

  describe '#initialize' do
    it 'sets default values' do
      default_service = described_class.new
      expect(default_service.instance_variable_get(:@namespace)).to eq('default')
      expect(default_service.instance_variable_get(:@timeout)).to eq(300)
    end

    it 'accepts custom values' do
      custom_service = described_class.new(namespace: 'custom', timeout: 600)
      expect(custom_service.instance_variable_get(:@namespace)).to eq('custom')
      expect(custom_service.instance_variable_get(:@timeout)).to eq(600)
    end
  end

  describe 'repository operations' do
    describe '#add_repository' do
      it 'adds a public repository' do
        expect(service).to receive(:execute_command).with('helm repo add stable https://charts.helm.sh/stable')
        service.add_repository('stable', 'https://charts.helm.sh/stable')
      end

      it 'adds a private repository with credentials' do
        expected_cmd = 'helm repo add private https://private.repo.com --username user --password pass'
        expect(service).to receive(:execute_command).with(expected_cmd)
        service.add_repository('private', 'https://private.repo.com', username: 'user', password: 'pass')
      end
    end

    describe '#update_repositories' do
      it 'updates all repositories' do
        expect(service).to receive(:execute_command).with('helm repo update')
        service.update_repositories
      end
    end

    describe '#list_repositories' do
      let(:json_response) { [{ 'name' => 'stable', 'url' => 'https://charts.helm.sh/stable' }].to_json }

      it 'returns parsed JSON' do
        expect(service).to receive(:execute_command).and_return(json_response)
        result = service.list_repositories
        expect(result).to eq([{ 'name' => 'stable', 'url' => 'https://charts.helm.sh/stable' }])
      end
    end
  end

  describe 'release operations' do
    describe '#install' do
      it 'installs a chart with basic options' do
        expected_cmd = 'helm install my-release stable/nginx --namespace test-namespace --create-namespace --timeout 300s'
        expect(service).to receive(:execute_command).with(expected_cmd)
        service.install('my-release', 'stable/nginx')
      end

      it 'installs with custom values' do
        expected_cmd = 'helm install my-release stable/nginx --namespace test-namespace --create-namespace --timeout 300s --set replicas=3 --set image.tag=latest'
        expect(service).to receive(:execute_command).with(expected_cmd)
        service.install('my-release', 'stable/nginx', values: { 'replicas' => 3, 'image.tag' => 'latest' })
      end

      it 'installs with values file' do
        expected_cmd = 'helm install my-release stable/nginx --namespace test-namespace --create-namespace --values /path/to/values.yaml --timeout 300s'
        expect(service).to receive(:execute_command).with(expected_cmd)
        service.install('my-release', 'stable/nginx', values_file: '/path/to/values.yaml')
      end
    end

    describe '#upgrade' do
      it 'upgrades a release' do
        expected_cmd = 'helm upgrade my-release stable/nginx --namespace test-namespace --install --timeout 300s'
        expect(service).to receive(:execute_command).with(expected_cmd)
        service.upgrade('my-release', 'stable/nginx')
      end
    end

    describe '#uninstall' do
      it 'uninstalls a release' do
        expected_cmd = 'helm uninstall my-release --namespace test-namespace --timeout 300s'
        expect(service).to receive(:execute_command).with(expected_cmd)
        service.uninstall('my-release')
      end

      it 'uninstalls with history kept' do
        expected_cmd = 'helm uninstall my-release --namespace test-namespace --keep-history --timeout 300s'
        expect(service).to receive(:execute_command).with(expected_cmd)
        service.uninstall('my-release', keep_history: true)
      end
    end

    describe '#list_releases' do
      let(:json_response) { [{ 'name' => 'my-release', 'status' => 'deployed' }].to_json }

      it 'returns list of releases' do
        expect(service).to receive(:execute_command).and_return(json_response)
        result = service.list_releases
        expect(result).to eq([{ 'name' => 'my-release', 'status' => 'deployed' }])
      end
    end

    describe '#get_release_status' do
      let(:json_response) { { 'name' => 'my-release', 'info' => { 'status' => 'deployed' } }.to_json }

      it 'returns release status' do
        expect(service).to receive(:execute_command).and_return(json_response)
        result = service.get_release_status('my-release')
        expect(result).to eq({ 'name' => 'my-release', 'info' => { 'status' => 'deployed' } })
      end
    end
  end

  describe 'error handling' do
    describe 'when command execution fails' do
      before do
        allow(service).to receive(:execute_command).and_call_original
        allow(service).to receive(:`).and_return('error message')
        allow($?).to receive(:exitstatus).and_return(1)
      end

      it 'raises ChartNotFoundError for chart not found' do
        allow(service).to receive(:`).and_return('chart not found')
        expect { service.install('test', 'nonexistent/chart') }.to raise_error(HelmService::ChartNotFoundError)
      end

      it 'raises ReleaseNotFoundError for release not found' do
        allow(service).to receive(:`).and_return('release test not found')
        expect { service.get_release_status('test') }.to raise_error(HelmService::ReleaseNotFoundError)
      end

      it 'raises CommandExecutionError for general failures' do
        allow(service).to receive(:`).and_return('general error')
        expect { service.install('test', 'chart') }.to raise_error(HelmService::CommandExecutionError)
      end
    end
  end

  describe '#template' do
    it 'generates templates' do
      expected_cmd = 'helm template my-release stable/nginx --namespace test-namespace'
      expect(service).to receive(:execute_command).with(expected_cmd)
      service.template('my-release', 'stable/nginx')
    end
  end

  describe '#dry_run' do
    it 'performs dry run installation' do
      expected_cmd = 'helm install my-release stable/nginx --namespace test-namespace --dry-run'
      expect(service).to receive(:execute_command).with(expected_cmd)
      service.dry_run('my-release', 'stable/nginx')
    end
  end
end