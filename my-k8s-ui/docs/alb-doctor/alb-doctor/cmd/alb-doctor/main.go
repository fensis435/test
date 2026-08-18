package main

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	awscollector "github.com/example/alb-doctor/internal/collector/aws"
	kcollector "github.com/example/alb-doctor/internal/collector/kubernetes"
	"github.com/example/alb-doctor/internal/diagnostic/rules"
	"github.com/example/alb-doctor/internal/kubeapi"
	"github.com/spf13/cobra"
	"os"
	"path/filepath"
)

func main() {
	var ns, ing, kc string
	root := &cobra.Command{Use: "alb-doctor"}
	cmd := &cobra.Command{Use: "ingress", RunE: func(cmd *cobra.Command, args []string) error {
		ctx := context.Background()
		k, e := kubeapi.NewClient(kc)
		if e != nil {
			return e
		}
		g, e := kcollector.New(k).Collect(ctx, ns, ing)
		if e != nil {
			return e
		}
		cfg, e := config.LoadDefaultConfig(ctx)
		if e != nil {
			return e
		}
		a := awscollector.New(elasticloadbalancingv2.NewFromConfig(cfg), ec2.NewFromConfig(cfg))
		if e = a.Collect(ctx, g); e != nil {
			return e
		}
		fs := rules.SGBlock(g)
		fmt.Printf("nodes=%d edges=%d findings=%d\n", len(g.Nodes), len(g.Edges), len(fs))
		for _, f := range fs {
			fmt.Printf("[%s] %s\n  %s\n", f.Severity, f.Title, f.Summary)
		}
		return nil
	}}
	cmd.Flags().StringVarP(&ns, "namespace", "n", "default", "namespace")
	cmd.Flags().StringVar(&ing, "ingress", "", "ingress name")
	cmd.Flags().StringVar(&kc, "kubeconfig", filepath.Join(os.Getenv("HOME"), ".kube", "config"), "kubeconfig")
	_ = cmd.MarkFlagRequired("ingress")
	root.AddCommand(cmd)
	if e := root.Execute(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
