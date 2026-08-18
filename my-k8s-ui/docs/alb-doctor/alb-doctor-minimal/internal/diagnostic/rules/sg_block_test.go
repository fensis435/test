package rules

import (
	"context"
	"testing"

	"github.com/example/alb-doctor/internal/diagnostic"
	"github.com/example/alb-doctor/internal/model"
)

func TestSGBlockRule(t *testing.T) {
	g := model.NewGraph()
	albSG := model.Resource{ID: "sg-alb", Kind: model.KindSecurityGroup, Attributes: map[string]any{
		"securityGroup": model.SecurityGroup{ID: "sg-alb"},
	}}
	targetSG := model.Resource{ID: "sg-target", Kind: model.KindSecurityGroup, Attributes: map[string]any{
		"securityGroup": model.SecurityGroup{ID: "sg-target"},
	}}
	alb := model.Resource{ID: "alb/demo", Kind: model.KindLoadBalancer}
	target := model.Resource{ID: "target/10.0.12.41:8080", Kind: model.KindTarget, Attributes: map[string]any{
		"port":   int32(8080),
		"health": model.TargetHealth{State: "unhealthy", Reason: "Target.Timeout"},
	}}
	for _, n := range []model.Resource{albSG, targetSG, alb, target} {
		g.AddNode(n)
	}
	g.AddEdge(model.Edge{From: albSG.ID, To: alb.ID, Kind: model.EdgeAttachedTo})
	g.AddEdge(model.Edge{From: targetSG.ID, To: target.ID, Kind: model.EdgeAttachedTo})
	g.AddEdge(model.Edge{From: alb.ID, To: target.ID, Kind: model.EdgeForwardsTo})

	findings := diagnostic.NewEngine(SGBlockRule{}).Run(context.Background(), g)
	if len(findings) != 1 {
		t.Fatalf("got %d findings, want 1", len(findings))
	}
	if findings[0].Severity != model.SeverityHigh {
		t.Fatalf("got severity %q", findings[0].Severity)
	}
}

func TestSGBlockRuleAllowed(t *testing.T) {
	g := model.NewGraph()
	albSG := model.Resource{ID: "sg-alb", Kind: model.KindSecurityGroup, Attributes: map[string]any{
		"securityGroup": model.SecurityGroup{ID: "sg-alb"},
	}}
	targetSG := model.Resource{ID: "sg-target", Kind: model.KindSecurityGroup, Attributes: map[string]any{
		"securityGroup": model.SecurityGroup{ID: "sg-target", Ingress: []model.SecurityGroupRule{{Protocol: "tcp", FromPort: 8080, ToPort: 8080, SourceSGIDs: []string{"sg-alb"}}}},
	}}
	alb := model.Resource{ID: "alb/demo", Kind: model.KindLoadBalancer}
	target := model.Resource{ID: "target/10.0.12.41:8080", Kind: model.KindTarget, Attributes: map[string]any{
		"port": int32(8080), "health": model.TargetHealth{State: "unhealthy", Reason: "Target.Timeout"},
	}}
	for _, n := range []model.Resource{albSG, targetSG, alb, target} {
		g.AddNode(n)
	}
	g.AddEdge(model.Edge{From: albSG.ID, To: alb.ID, Kind: model.EdgeAttachedTo})
	g.AddEdge(model.Edge{From: targetSG.ID, To: target.ID, Kind: model.EdgeAttachedTo})
	g.AddEdge(model.Edge{From: alb.ID, To: target.ID, Kind: model.EdgeForwardsTo})

	findings := diagnostic.NewEngine(SGBlockRule{}).Run(context.Background(), g)
	if len(findings) != 0 {
		t.Fatalf("got %d findings, want 0", len(findings))
	}
}
