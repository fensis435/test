POD=gui-deployment-5b6b97c9b7-6hgkf
CLUSTER_IP=10.107.70.236   # 現在の ClusterIP を変数に入れる
kubectl get configmap envoy-gui-config -o yaml > /tmp/envoy-gui-config.yaml
sed -i "s/10.107.70.236/subweb-service.default.svc.cluster.local/g" /tmp/envoy-gui-config.yaml
kubectl apply -f /tmp/envoy-gui-config.yaml
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
