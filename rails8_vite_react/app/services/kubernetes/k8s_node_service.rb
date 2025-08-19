# app/services/kubernetes/node_service.rb
module Kubernetes
  class NodeService < BaseService
    class << self
      def list_nodes(label_selector: nil, field_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        options[:fieldSelector] = field_selector if field_selector.present?
        
        core_v1_client.resource('nodes').list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node', 'list')
      end
      
      def get_node(name)
        core_v1_client.resource('nodes').get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node', name)
      end
      
      def get_node_status(name)
        node = get_node(name)
        return nil unless node
        
        {
          name: node.metadata.name,
          ready: node_ready?(node),
          conditions: node.status&.conditions,
          addresses: node.status&.addresses,
          capacity: node.status&.capacity,
          allocatable: node.status&.allocatable,
          node_info: node.status&.nodeInfo,
          taints: node.spec&.taints,
          unschedulable: node.spec&.unschedulable || false
        }
      end
      
      def drain_node(name, force: false, delete_emptydir_data: false, ignore_daemonsets: true)
        # This is a simplified version of node draining
        # In a real implementation, you'd want to use kubectl drain logic
        
        # First, mark node as unschedulable
        cordon_node(name)
        
        # Get all pods on the node
        pods = PodService.list_pods(field_selector: "spec.nodeName=#{name}")
        return false unless pods
        
        # Filter out system pods if necessary
        pods_to_delete = pods.reject do |pod|
          # Skip if it's a DaemonSet pod and we're ignoring them
          if ignore_daemonsets && pod.metadata&.ownerReferences&.any? { |ref| ref.kind == 'DaemonSet' }
            true
          # Skip if it has local storage and we're not forcing deletion
          elsif !delete_emptydir_data && has_local_storage?(pod)
            !force
          else
            false
          end
        end
        
        # Delete the pods
        pods_to_delete.each do |pod|
          PodService.delete_pod(pod.metadata.name, namespace: pod.metadata.namespace, force: force)
        end
        
        # Wait for pods to be terminated
        timeout = 300
        start_time = Time.current
        
        loop do
          remaining_pods = PodService.list_pods(field_selector: "spec.nodeName=#{name}")
          break if !remaining_pods || remaining_pods.empty?
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout draining node #{name}, some pods may still be running"
            break
          end
          
          sleep 5
        end
        
        true
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node drain', name)
        false
      end
      
      def cordon_node(name)
        node = get_node(name)
        return false unless node
        
        node.spec ||= {}
        node.spec.unschedulable = true
        
        core_v1_client.resource('nodes').update_resource(node)
        true
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node cordon', name)
        false
      end
      
      def uncordon_node(name)
        node = get_node(name)
        return false unless node
        
        node.spec ||= {}
        node.spec.unschedulable = false
        
        core_v1_client.resource('nodes').update_resource(node)
        true
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node uncordon', name)
        false
      end
      
      def taint_node(name, key, value, effect)
        node = get_node(name)
        return false unless node
        
        node.spec ||= {}
        node.spec.taints ||= []
        
        # Remove existing taint with same key if exists
        node.spec.taints.reject! { |taint| taint.key == key }
        
        # Add new taint
        new_taint = {
          key: key,
          value: value,
          effect: effect
        }
        node.spec.taints << new_taint
        
        core_v1_client.resource('nodes').update_resource(node)
        true
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node taint', name)
        false
      end
      
      def untaint_node(name, key)
        node = get_node(name)
        return false unless node
        
        return true unless node.spec&.taints
        
        node.spec.taints.reject! { |taint| taint.key == key }
        
        core_v1_client.resource('nodes').update_resource(node)
        true
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node untaint', name)
        false
      end
      
      def label_node(name, labels)
        node = get_node(name)
        return false unless node
        
        node.metadata.labels ||= {}
        node.metadata.labels.merge!(labels)
        
        core_v1_client.resource('nodes').update_resource(node)
        true
      rescue K8s::Error => e
        handle_k8s_error(e, 'Node label', name)
        false
      end
      
      def get_node_pods(name)
        PodService.list_pods(field_selector: "spec.nodeName=#{name}")
      end
      
      def get_node_resource_usage(name)
        # This requires metrics-server to be installed
        begin
          node_metric = MonitoringService.get_node_metrics.find { |nm| nm.metadata.name == name }
          node = get_node(name)
          
          return nil unless node_metric && node
          
          {
            name: name,
            usage: {
              cpu: node_metric.usage&.cpu,
              memory: node_metric.usage&.memory
            },
            capacity: {
              cpu: node.status&.capacity&.cpu,
              memory: node.status&.capacity&.memory
            },
            allocatable: {
              cpu: node.status&.allocatable&.cpu,
              memory: node.status&.allocatable&.memory
            }
          }
        rescue StandardError => e
          Rails.logger.error "Failed to get node resource usage: #{e.message}"
          nil
        end
      end
      
      def get_cluster_summary
        nodes = list_nodes
        return nil unless nodes
        
        summary = {
          total_nodes: nodes.length,
          ready_nodes: 0,
          not_ready_nodes: 0,
          schedulable_nodes: 0,
          unschedulable_nodes: 0,
          capacity: { cpu: 0, memory: 0, pods: 0 },
          allocatable: { cpu: 0, memory: 0, pods: 0 }
        }
        
        nodes.each do |node|
          # Count ready/not ready
          if node_ready?(node)
            summary[:ready_nodes] += 1
          else
            summary[:not_ready_nodes] += 1
          end
          
          # Count schedulable/unschedulable
          if node.spec&.unschedulable
            summary[:unschedulable_nodes] += 1
          else
            summary[:schedulable_nodes] += 1
          end
          
          # Sum capacity and allocatable resources
          if node.status&.capacity
            summary[:capacity][:cpu] += parse_cpu_value(node.status.capacity.cpu)
            summary[:capacity][:memory] += parse_memory_value(node.status.capacity.memory)
            summary[:capacity][:pods] += node.status.capacity.pods.to_i if node.status.capacity.pods
          end
          
          if node.status&.allocatable
            summary[:allocatable][:cpu] += parse_cpu_value(node.status.allocatable.cpu)
            summary[:allocatable][:memory] += parse_memory_value(node.status.allocatable.memory)
            summary[:allocatable][:pods] += node.status.allocatable.pods.to_i if node.status.allocatable.pods
          end
        end
        
        summary
      end
      
      def node_ready?(node)
        return false unless node.status&.conditions
        
        ready_condition = node.status.conditions.find { |condition| condition.type == 'Ready' }
        ready_condition&.status == 'True'
      end
      
      private
      
      def has_local_storage?(pod)
        return false unless pod.spec&.volumes
        
        pod.spec.volumes.any? do |volume|
          volume.emptyDir || volume.hostPath
        end
      end
      
      def parse_cpu_value(cpu_string)
        return 0 unless cpu_string
        
        case cpu_string
        when /(\d+)m$/
          $1.to_i
        when /(\d+)$/
          $1.to_i * 1000
        when /(\d*\.?\d+)$/
          ($1.to_f * 1000).to_i
        else
          0
        end
      end
      
      def parse_memory_value(memory_string)
        return 0 unless memory_string
        
        case memory_string
        when /(\d+)Ki?$/i
          $1.to_i * 1024
        when /(\d+)Mi?$/i
          $1.to_i * 1024 * 1024
        when /(\d+)Gi?$/i
          $1.to_i * 1024 * 1024 * 1024
        when /(\d+)Ti?$/i
          $1.to_i * 1024 * 1024 * 1024 * 1024
        when /(\d+)$/
          $1.to_i
        else
          0
        end
      end
    end
  end
end