# alb-doctor

Minimal EKS + AWS Load Balancer Controller diagnostic CLI.

## What is implemented

The collector builds this path when the target type is IP:

`Ingress -> Service -> EndpointSlice -> Pod`

and joins it to AWS:

`TargetGroupBinding -> TargetGroup -> TargetHealth(Target IP) -> ENI -> SecurityGroup`

Then it discovers application load balancers, listeners and listener rules and joins a TargetGroup to the ALB when a listener rule forwards to that target group:

`TargetGroup -> Listener Rule -> ALB -> SecurityGroup`

The first diagnostic rule checks whether the target SG allows TCP traffic from any ALB SG on the target-group port, either by SG reference or by CIDR.

## Run

```bash
go mod tidy
go test ./...
go run ./cmd/alb-doctor ingress -n production --ingress my-api
```

AWS credentials use the normal AWS SDK credential chain. Kubernetes uses the kubeconfig passed with `--kubeconfig` (default `$HOME/.kube/config`).

## Important limitation

This MVP resolves the requested `Target IP -> ENI` path. If the TargetGroup uses `instance` target type, the target identifier is an EC2 instance ID rather than a Pod IP, so the ENI resolution needs an additional `instance-id -> primary ENI` branch. Add that before treating instance-mode ALBC deployments as fully supported.
