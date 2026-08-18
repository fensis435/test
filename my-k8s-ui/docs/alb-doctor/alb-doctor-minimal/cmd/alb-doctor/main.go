package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/example/alb-doctor/internal/diagnostic"
	"github.com/example/alb-doctor/internal/diagnostic/rules"
	"github.com/example/alb-doctor/internal/model"
	"github.com/spf13/cobra"
)

func main() {
	root := &cobra.Command{Use: "alb-doctor", Short: "Evidence-driven EKS ALB diagnostics"}
	root.AddCommand(demoCommand())
	if err := root.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func demoCommand() *cobra.Command {
	return &cobra.Command{
		Use: "demo", Short: "run sg-block against an in-memory graph",
		RunE: func(cmd *cobra.Command, _ []string) error {
			g := model.NewGraph()
			alb := model.Resource{ID: "sg-alb", Kind: model.KindSecurityGroup, Name: "alb-sg", Attributes: map[string]any{"securityGroup": model.SecurityGroup{ID: "sg-alb"}}}
			targetSG := model.Resource{ID: "sg-target", Kind: model.KindSecurityGroup, Name: "target-sg", Attributes: map[string]any{"securityGroup": model.SecurityGroup{ID: "sg-target", Ingress: []model.SecurityGroupRule{}}}}
			target := model.Resource{ID: "target/10.0.12.41:8080", Kind: model.KindTarget, Attributes: map[string]any{"ip": "10.0.12.41", "port": int32(8080), "health": model.TargetHealth{State: "unhealthy", Reason: "Target.Timeout"}}}
			g.AddNode(alb)
			g.AddNode(targetSG)
			g.AddNode(target)
			albNode := model.Resource{ID: "alb/demo", Kind: model.KindLoadBalancer, Name: "demo-alb"}
			g.AddNode(albNode)
			g.AddEdge(model.Edge{From: targetSG.ID, To: target.ID, Kind: model.EdgeAttachedTo})
			g.AddEdge(model.Edge{From: alb.ID, To: albNode.ID, Kind: model.EdgeAttachedTo})
			g.AddEdge(model.Edge{From: albNode.ID, To: target.ID, Kind: model.EdgeForwardsTo})
			findings := diagnostic.NewEngine(rules.SGBlockRule{}).Run(context.Background(), g)
			b, _ := json.MarshalIndent(findings, "", "  ")
			fmt.Println(string(b))
			return nil
		},
	}
}
