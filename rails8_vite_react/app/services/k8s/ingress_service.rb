class K8s::IngressService < K8s::BaseService
  def create_ingress(name:, namespace:, host:, service_name:, service_port:, tls: true)
    handle_k8s_error do
      ingress = build_ingress_resource(
        name: name,
        namespace: namespace,
        host: host,
        service_name: service_name,
        service_port: service_port,
        tls: tls
      )
      
      k8s_networking_client.create_ingress(ingress)
      Rails.logger.info "Created ingress: #{name} for host: #{host} in namespace: #{namespace}"
    end
  end

  def delete_ingress(name:, namespace:)
    handle_k8s_error do
      k8s_networking_client.delete_ingress(name, namespace)
      Rails.logger.info "Deleted ingress: #{name} in namespace: #{namespace}"
    end
  end

  def get_ingress(name:, namespace:)
    handle_k8s_error do
      ingress = k8s_networking_client.get_ingress(name, namespace)
      {
        'metadata' => {
          'name' => ingress.metadata.name,
          'namespace' => ingress.metadata.namespace
        },
        'spec' => ingress.spec.to_h,
        'status' => ingress.status&.to_h
      }
    end
  end

  def exists?(name:, namespace:)
    handle_k8s_error do
      k8s_networking_client.get_ingress(name, namespace)
      true
    end
  rescue K8sError
    false
  end

  private

  def build_ingress_resource(name:, namespace:, host:, service_name:, service_port:, tls:)
    ingress_spec = {
      rules: [{
        host: host,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: service_name,
                port: {
                  number: service_port
                }
              }
            }
          }]
        }
      }]
    }

    if tls
      ingress_spec[:tls] = [{
        hosts: [host],
        secretName: "#{name}-tls"
      }]
    end

    Kubeclient::Resource.new(
      metadata: {
        name: name,
        namespace: namespace,
        annotations: {
          'kubernetes.io/ingress.class' => 'nginx',
          'nginx.ingress.kubernetes.io/rewrite-target' => '/$1'
        }
      },
      spec: ingress_spec
    )
  end
end
