# alb-doctor

Minimal proof-of-concept for an evidence-driven EKS + AWS Load Balancer Controller diagnostic engine.

## Current scope

- Canonical Graph / Evidence / Finding model
- Diagnostic Rule interface
- First deterministic rule: `sg-block`
- Kubernetes client skeleton + TargetGroupBinding discovery
- AWS ELBv2 / EC2 client interfaces
- `alb-doctor demo` executable fixture

## Run

```bash
go mod tidy
go test ./...
go run ./cmd/alb-doctor demo
```

The demo intentionally constructs:

```text
ALB -> Target
ALB-SG -> ALB
Target-SG -> Target
```

and reports a HIGH finding because Target-SG has no TCP/8080 ingress from ALB-SG.

## Next implementation step

Replace the demo graph with collectors that populate:

```text
Ingress -> Service -> EndpointSlice -> Pod
                         |
                         v
                  TargetGroupBinding
                         |
                         v
                    TargetGroup
                         |
                         v
                       Target
                         |
                         v
                        ENI
                         |
                         v
                         SG
```

TargetGroupBinding is the primary Kubernetes-to-AWS join point used by AWS Load Balancer Controller.
