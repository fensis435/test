package rules

import (
	"context"
	"fmt"

	"github.com/example/alb-doctor/internal/model"
)

type SGBlockRule struct{}

func (SGBlockRule) ID() string { return "sg-block" }

// Evaluate detects the common case where an AWS Target reports Target.Timeout
// and no inbound rule on the target ENI's SG allows traffic from the ALB SG.
// The graph is expected to contain:
//
//	ALB --forwards-to--> Target
//	ALB-SG --attached-to--> ALB
//	Target-SG --attached-to--> Target
func (SGBlockRule) Evaluate(_ context.Context, g *model.Graph) []model.Finding {
	var findings []model.Finding
	for _, target := range g.Nodes {
		if target.Kind != model.KindTarget {
			continue
		}
		health, ok := target.Attributes["health"].(model.TargetHealth)
		if !ok || health.State == "healthy" || health.Reason != "Target.Timeout" {
			continue
		}
		port, ok := target.Attributes["port"].(int32)
		if !ok {
			continue
		}

		targetSG, ok := securityGroupAttachedTo(g, target.ID)
		if !ok {
			continue
		}
		albID, ok := upstreamALB(g, target.ID)
		if !ok {
			continue
		}
		albSG, ok := securityGroupAttachedTo(g, albID)
		if !ok {
			continue
		}
		if allowsSG(albSG, targetSG, "tcp", port) {
			continue
		}

		findings = append(findings, model.Finding{
			ID:       "sg-block/" + string(target.ID),
			Severity: model.SeverityHigh,
			Title:    "Security Group blocks ALB to target traffic",
			Summary: fmt.Sprintf(
				"target %s is unhealthy and %s has no ingress rule allowing TCP/%d from %s",
				target.ID, targetSG.ID, port, albSG.ID,
			),
			RootCause: []model.ResourceID{target.ID, model.ResourceID(targetSG.ID), model.ResourceID(albSG.ID)},
			Evidence: []model.Evidence{
				{Source: model.SourceAWS, ResourceID: string(target.ID), Field: "TargetHealth.Reason", Value: health.Reason, Description: "AWS Target Health reports timeout"},
				{Source: model.SourceAWS, ResourceID: targetSG.ID, Field: "ingress", Value: targetSG.Ingress, Description: "No matching ingress rule was found"},
			},
			Remediation: &model.Remediation{
				Description: fmt.Sprintf("Allow TCP/%d from %s on %s", port, albSG.ID, targetSG.ID),
				Safe:        false,
			},
		})
	}
	return findings
}

func upstreamALB(g *model.Graph, targetID model.ResourceID) (model.ResourceID, bool) {
	for _, e := range g.Edges {
		if e.Kind == model.EdgeForwardsTo && e.To == targetID {
			if n, ok := g.Nodes[e.From]; ok && n.Kind == model.KindLoadBalancer {
				return e.From, true
			}
		}
	}
	return "", false
}

func securityGroupAttachedTo(g *model.Graph, resourceID model.ResourceID) (*model.SecurityGroup, bool) {
	for _, e := range g.Edges {
		if e.Kind != model.EdgeAttachedTo || e.To != resourceID {
			continue
		}
		n, ok := g.Nodes[e.From]
		if !ok || n.Kind != model.KindSecurityGroup {
			continue
		}
		sg, ok := n.Attributes["securityGroup"].(model.SecurityGroup)
		if ok {
			return &sg, true
		}
	}
	return nil, false
}

func allowsSG(source, destination *model.SecurityGroup, protocol string, port int32) bool {
	for _, r := range destination.Ingress {
		if r.Protocol != "-1" && r.Protocol != protocol {
			continue
		}
		if r.Protocol != "-1" && (port < r.FromPort || port > r.ToPort) {
			continue
		}
		for _, id := range r.SourceSGIDs {
			if id == source.ID {
				return true
			}
		}
	}
	return false
}
