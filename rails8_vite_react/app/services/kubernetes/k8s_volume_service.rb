# app/services/kubernetes/volume_service.rb
module Kubernetes
  class VolumeService < BaseService
    class << self
      # PersistentVolume operations
      def list_persistent_volumes(label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        core_v1_client.resource('persistentvolumes').list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolume', 'list')
      end
      
      def get_persistent_volume(name)
        core_v1_client.resource('persistentvolumes').get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolume', name)
      end
      
      def create_persistent_volume(spec)
        pv_manifest = build_persistent_volume_manifest(spec)
        core_v1_client.resource('persistentvolumes').create_resource(pv_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolume', spec[:name])
      end
      
      def delete_persistent_volume(name)
        core_v1_client.resource('persistentvolumes').delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolume', name)
      end
      
      # PersistentVolumeClaim operations
      def list_persistent_volume_claims(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        core_v1_client.resource('persistentvolumeclaims', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolumeClaim', 'list')
      end
      
      def get_persistent_volume_claim(name, namespace: 'default')
        core_v1_client.resource('persistentvolumeclaims', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolumeClaim', name)
      end
      
      def create_persistent_volume_claim(spec, namespace: 'default')
        pvc_manifest = build_persistent_volume_claim_manifest(spec, namespace)
        core_v1_client.resource('persistentvolumeclaims', namespace: validate_namespace(namespace))
                     .create_resource(pvc_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolumeClaim', spec[:name])
      end
      
      def delete_persistent_volume_claim(name, namespace: 'default')
        core_v1_client.resource('persistentvolumeclaims', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PersistentVolumeClaim', name)
      end
      
      def get_pvc_status(name, namespace: 'default')
        pvc = get_persistent_volume_claim(name, namespace)
        return nil unless pvc
        
        {
          phase: pvc.status&.phase,
          access_modes: pvc.status&.accessModes,
          capacity: pvc.status&.capacity,
          volume_name: pvc.spec&.volumeName,
          storage_class: pvc.spec&.storageClassName,
          bound: pvc.status&.phase == 'Bound'
        }
      end
      
      def wait_for_pvc_bound(name, namespace: 'default', timeout: 300)
        start_time = Time.current
        
        loop do
          pvc = get_persistent_volume_claim(name, namespace)
          return false unless pvc
          return true if pvc.status&.phase == 'Bound'
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout waiting for PVC #{name} to be bound"
            return false
          end
          
          sleep 5
        end
      end
      
      # StorageClass operations
      def list_storage_classes(label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        client.api('storage.k8s.io/v1').resource('storageclasses').list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'StorageClass', 'list')
      end
      
      def get_storage_class(name)
        client.api('storage.k8s.io/v1').resource('storageclasses').get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'StorageClass', name)
      end
      
      def create_storage_class(spec)
        sc_manifest = build_storage_class_manifest(spec)
        client.api('storage.k8s.io/v1').resource('storageclasses').create_resource(sc_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'StorageClass', spec[:name])
      end
      
      def delete_storage_class(name)
        client.api('storage.k8s.io/v1').resource('storageclasses').delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'StorageClass', name)
      end
      
      # Volume snapshot operations (if supported)
      def list_volume_snapshots(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        client.api('snapshot.storage.k8s.io/v1').resource('volumesnapshots', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'VolumeSnapshot', 'list')
      end
      
      def create_volume_snapshot(name, pvc_name, snapshot_class: nil, namespace: 'default')
        snapshot_manifest = {
          apiVersion: 'snapshot.storage.k8s.io/v1',
          kind: 'VolumeSnapshot',
          metadata: {
            name: name,
            namespace: validate_namespace(namespace),
            labels: build_labels({})
          },
          spec: {
            source: {
              persistentVolumeClaimName: pvc_name
            },
            volumeSnapshotClassName: snapshot_class
          }.compact
        }
        
        client.api('snapshot.storage.k8s.io/v1').resource('volumesnapshots', namespace: validate_namespace(namespace))
              .create_resource(snapshot_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'VolumeSnapshot', name)
      end
      
      # Utility methods for common volume patterns
      def create_hostpath_pv(name, path, capacity, access_modes: ['ReadWriteOnce'])
        spec = {
          name: name,
          capacity: { storage: capacity },
          access_modes: access_modes,
          reclaim_policy: 'Retain',
          host_path: { path: path }
        }
        
        create_persistent_volume(spec)
      end
      
      def create_nfs_pv(name, server, path, capacity, access_modes: ['ReadWriteMany'])
        spec = {
          name: name,
          capacity: { storage: capacity },
          access_modes: access_modes,
          reclaim_policy: 'Retain',
          nfs: { server: server, path: path }
        }
        
        create_persistent_volume(spec)
      end
      
      def create_simple_pvc(name, size, storage_class: nil, access_modes: ['ReadWriteOnce'], namespace: 'default')
        spec = {
          name: name,
          access_modes: access_modes,
          resources: { requests: { storage: size } },
          storage_class: storage_class
        }
        
        create_persistent_volume_claim(spec, namespace)
      end
      
      def resize_pvc(name, new_size, namespace: 'default')
        pvc = get_persistent_volume_claim(name, namespace)
        return nil unless pvc
        
        pvc.spec.resources.requests.storage = new_size
        
        core_v1_client.resource('persistentvolumeclaims', namespace: validate_namespace(namespace))
                     .update_resource(pvc)
      rescue K8s::Error => e
        handle_k8s_error(e, 'PVC resize', name)
      end
      
      def get_volume_usage_stats(namespace: 'default')
        # This would typically require metrics-server or custom monitoring
        # Returning basic info from PVCs
        pvcs = list_persistent_volume_claims(namespace: namespace)
        return [] unless pvcs
        
        stats = []
        pvcs.each do |pvc|
          stats << {
            name: pvc.metadata.name,
            namespace: pvc.metadata.namespace,
            storage_class: pvc.spec&.storageClassName,
            requested_storage: pvc.spec&.resources&.requests&.storage,
            status: pvc.status&.phase,
            volume_name: pvc.spec&.volumeName
          }
        end
        
        stats
      end
      
      private
      
      def build_persistent_volume_manifest(spec)
        {
          apiVersion: 'v1',
          kind: 'PersistentVolume',
          metadata: {
            name: spec[:name],
            labels: build_labels(spec[:labels] || {})
          },
          spec: {
            capacity: spec[:capacity],
            accessModes: spec[:access_modes],
            persistentVolumeReclaimPolicy: spec[:reclaim_policy] || 'Retain',
            storageClassName: spec[:storage_class],
            mountOptions: spec[:mount_options],
            nodeAffinity: spec[:node_affinity],
            # Volume source (one of these)
            hostPath: spec[:host_path],
            nfs: spec[:nfs],
            iscsi: spec[:iscsi],
            glusterfs: spec[:glusterfs],
            cephfs: spec[:cephfs],
            awsElasticBlockStore: spec[:aws_ebs],
            gcePersistentDisk: spec[:gce_pd],
            azureDisk: spec[:azure_disk],
            azureFile: spec[:azure_file],
            csi: spec[:csi]
          }.compact
        }
      end
      
      def build_persistent_volume_claim_manifest(spec, namespace)
        {
          apiVersion: 'v1',
          kind: 'PersistentVolumeClaim',
          metadata: {
            name: spec[:name],
            namespace: validate_namespace(namespace),
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          spec: {
            accessModes: spec[:access_modes] || ['ReadWriteOnce'],
            resources: spec[:resources] || { requests: { storage: '1Gi' } },
            storageClassName: spec[:storage_class],
            selector: spec[:selector],
            volumeName: spec[:volume_name],
            dataSource: spec[:data_source]
          }.compact
        }
      end
      
      def build_storage_class_manifest(spec)
        {
          apiVersion: 'storage.k8s.io/v1',
          kind: 'StorageClass',
          metadata: {
            name: spec[:name],
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          provisioner: spec[:provisioner],
          parameters: spec[:parameters] || {},
          reclaimPolicy: spec[:reclaim_policy] || 'Delete',
          allowVolumeExpansion: spec[:allow_volume_expansion] || false,
          volumeBindingMode: spec[:volume_binding_mode] || 'Immediate',
          allowedTopologies: spec[:allowed_topologies],
          mountOptions: spec[:mount_options]
        }.compact
      end
    end
  end
end