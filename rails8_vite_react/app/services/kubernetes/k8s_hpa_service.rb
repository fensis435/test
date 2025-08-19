# app/services/kubernetes/autoscaling_service.rb
module Kubernetes
  class AutoscalingService < BaseService
    class << self
      # HorizontalPodAutoscaler operations
      def list_hpas(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        autoscaling_v1_client.resource('horizontalpodautoscalers', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'HorizontalPodAutoscaler', 'list')
      end
      
      def get_hpa(name, namespace: 'default')
        autoscaling_v1_client.resource('horizontalpodautoscalers', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'HorizontalPodAutoscaler', name)
      end
      
      def create_hpa(spec, namespace: 'default')
        hpa_manifest = build_hpa_manifest(spec, namespace)
        autoscaling_v1_client.resource('horizontalpodautoscalers', namespace: validate_namespace(namespace))
                           .create_resource(hpa_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'HorizontalPodAutoscaler', spec[:name])
      end
      
      def update_hpa(name, spec, namespace: 'default')
        hpa = get_hpa(name, namespace)
        return nil unless hpa
        
        hpa.spec.minReplicas = spec[:min_replicas] if spec[:min_replicas]
        hpa.spec.maxReplicas = spec[:max_replicas] if spec[:max_replicas]
        hpa.spec.targetCPUUtilizationPercentage = spec[:target_cpu_percentage] if spec[:target_cpu_percentage]
        
        autoscaling_v1_client.resource('horizontalpodautoscalers', namespace: validate_namespace(namespace))
                           .update_resource(hpa)
      rescue K8s::Error => e
        handle_k8s_error(e, 'HorizontalPodAutoscaler', name)
      end
      
      def delete_hpa(name, namespace: 'default')
        autoscaling_v1_client.resource('horizontalpodautoscalers', namespace: validate_namespace(namespace))
                           .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'HorizontalPodAutoscaler', name)
      end
      
      def get_hpa_status(name, namespace: 'default')
        hpa = get_hpa(name, namespace)
        return nil unless hpa
        
        {
          current_replicas: hpa.status&.currentReplicas,
          desired_replicas: hpa.status&.desiredReplicas,
          current_cpu_utilization: hpa.status&.currentCPUUtilizationPercentage,
          target_cpu_utilization: hpa.spec&.targetCPUUtilizationPercentage,
          min_replicas: hpa.spec&.minReplicas,
          max_replicas: hpa.spec&.maxReplicas,
          conditions: hpa.status&.conditions,
          last_scale_time: hpa.status&.lastScaleTime
        }
      end
      
      # Advanced HPA with custom metrics (v2 API)
      def create_advanced_hpa(spec, namespace: 'default')
        hpa_manifest = build_advanced_hpa_manifest(spec, namespace)
        client.api('autoscaling/v2').resource('horizontalpodautoscalers', namespace: validate_namespace(namespace))
              .create_resource(hpa_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'HorizontalPodAutoscaler v2', spec[:name])
      end
      
      def create_cpu_hpa(name, target_name, target_kind: 'Deployment', min_replicas: 1, max_replicas: 10, target_cpu: 80, namespace: 'default')
        spec = {
          name: name,
          target_name: target_name,
          target_kind: target_kind,
          min_replicas: min_replicas,
          max_replicas: max_replicas,
          target_cpu_percentage: target_cpu
        }
        
        create_hpa(spec, namespace)
      end
      
      def create_memory_hpa(name, target_name, target_kind: 'Deployment', min_replicas: 1, max_replicas: 10, target_memory: '100Mi', namespace: 'default')
        spec = {
          name: name,
          target_name: target_name,
          target_kind: target_kind,
          min_replicas: min_replicas,
          max_replicas: max_replicas,
          metrics: [
            {
              type: 'Resource',
              resource: {
                name: 'memory',
                target: {
                  type: 'AverageValue',
                  averageValue: target_memory
                }
              }
            }
          ]
        }
        
        create_advanced_hpa(spec, namespace)
      end
    end
  end
  
  # Monitoring and metrics service
  class MonitoringService < BaseService
    class << self
      # Node metrics (requires metrics-server)
      def get_node_metrics
        client.api('metrics.k8s.io/v1beta1').resource('nodes').list
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node metrics', 'list')
      end
      
      def get_pod_metrics(namespace: 'default')
        client.api('metrics.k8s.io/v1beta1').resource('pods', namespace: validate_namespace(namespace)).list
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod metrics', 'list')
      end
      
      def get_pod_metric(name, namespace: 'default')
        client.api('metrics.k8s.io/v1beta1').resource('pods', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod metrics', name)
      end
      
      # Resource usage analysis
      def analyze_cluster_resources
        nodes = NodeService.list_nodes
        node_metrics = get_node_metrics
        
        return nil unless nodes && node_metrics
        
        analysis = {
          total_nodes: nodes.length,
          node_resources: [],
          cluster_totals: {
            cpu: { allocatable: 0, usage: 0 },
            memory: { allocatable: 0, usage: 0 }
          }
        }
        
        nodes.each do |node|
          node_name = node.metadata.name
          node_metric = node_metrics.find { |nm| nm.metadata.name == node_name }
          
          allocatable_cpu = parse_cpu_value(node.status&.allocatable&.cpu)
          allocatable_memory = parse_memory_value(node.status&.allocatable&.memory)
          
          usage_cpu = node_metric ? parse_cpu_value(node_metric.usage&.cpu) : 0
          usage_memory = node_metric ? parse_memory_value(node_metric.usage&.memory) : 0
          
          node_info = {
            name: node_name,
            allocatable: {
              cpu: allocatable_cpu,
              memory: allocatable_memory
            },
            usage: {
              cpu: usage_cpu,
              memory: usage_memory
            },
            utilization: {
              cpu: allocatable_cpu > 0 ? (usage_cpu.to_f / allocatable_cpu * 100).round(2) : 0,
              memory: allocatable_memory > 0 ? (usage_memory.to_f / allocatable_memory * 100).round(2) : 0
            }
          }
          
          analysis[:node_resources] << node_info
          analysis[:cluster_totals][:cpu][:allocatable] += allocatable_cpu
          analysis[:cluster_totals][:cpu][:usage] += usage_cpu
          analysis[:cluster_totals][:memory][:allocatable] += allocatable_memory
          analysis[:cluster_totals][:memory][:usage] += usage_memory
        end
        
        # Calculate cluster-wide utilization
        total_cpu = analysis[:cluster_totals][:cpu]
        total_memory = analysis[:cluster_totals][:memory]
        
        analysis[:cluster_utilization] = {
          cpu: total_cpu[:allocatable] > 0 ? (total_cpu[:usage].to_f / total_cpu[:allocatable] * 100).round(2) : 0,
          memory: total_memory[:allocatable] > 0 ? (total_memory[:usage].to_f / total_memory[:allocatable] * 100).round(2) : 0
        }
        
        analysis
      end
      
      def analyze_namespace_resources(namespace: 'default')
        pods = PodService.list_pods(namespace: namespace)
        pod_metrics = get_pod_metrics(namespace: namespace)
        
        return nil unless pods
        
        analysis = {
          namespace: namespace,
          total_pods: pods.length,
          pod_resources: [],
          namespace_totals: {
            cpu: { requests: 0, limits: 0, usage: 0 },
            memory: { requests: 0, limits: 0, usage: 0 }
          }
        }
        
        pods.each do |pod|
          pod_name = pod.metadata.name
          pod_metric = pod_metrics&.find { |pm| pm.metadata.name == pod_name }
          
          pod_info = {
            name: pod_name,
            requests: { cpu: 0, memory: 0 },
            limits: { cpu: 0, memory: 0 },
            usage: { cpu: 0, memory: 0 }
          }
          
          # Calculate requests and limits
          pod.spec&.containers&.each do |container|
            if container.resources&.requests
              pod_info[:requests][:cpu] += parse_cpu_value(container.resources.requests.cpu)
              pod_info[:requests][:memory] += parse_memory_value(container.resources.requests.memory)
            end
            
            if container.resources&.limits
              pod_info[:limits][:cpu] += parse_cpu_value(container.resources.limits.cpu)
              pod_info[:limits