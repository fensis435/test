module github.com/example/alb-doctor

go 1.24

require (
	github.com/aws/aws-sdk-go-v2 v1.43.2
	github.com/aws/aws-sdk-go-v2/config v1.32.31
	github.com/aws/aws-sdk-go-v2/service/ec2 v1.318.0
	github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2 v1.55.6
	github.com/spf13/cobra v1.10.2
	k8s.io/api v0.36.3
	k8s.io/apimachinery v0.36.3
	k8s.io/client-go v0.36.3
)
