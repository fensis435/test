package rules

import (
	"fmt"
	"github.com/example/alb-doctor/internal/model"
	"net"
)

func SGBlock(g *model.Graph) []model.Finding {
	var fs []model.Finding
	for _, t := range g.Nodes {
		if t.Kind != model.KindTarget {
			continue
		}
		h, ok := t.Attributes["health"].(model.TargetHealth)
		if !ok || h.State == "healthy" {
			continue
		}
		p, ok := t.Attributes["port"].(int32)
		if !ok {
			continue
		}
		eni := neighbor(g, t.ID, model.KindNetworkInterface)
		if eni == "" {
			continue
		}
		ts := strs(g.Nodes[eni].Attributes["securityGroupIDs"])
		for _, lb := range g.Nodes {
			if lb.Kind != model.KindLoadBalancer || !connectedTG(g, t.ID, lb.ID) {
				continue
			}
			ss := strs(lb.Attributes["securityGroupIDs"])
			if allowed(g, ss, ts, t, p) {
				continue
			}
			fs = append(fs, model.Finding{ID: "sg-block/" + string(t.ID) + "/" + string(lb.ID), Severity: model.SeverityHigh, Title: "Security Group blocks ALB to target traffic", Summary: fmt.Sprintf("Target %s:%d is %s and no target SG ingress rule permits traffic from the ALB SGs.", t.Name, p, h.State), RootCause: []model.ResourceID{lb.ID, eni}})
		}
	}
	return fs
}
func connectedTG(g *model.Graph, target, lb model.ResourceID) bool {
	t, ok := g.Nodes[target]
	if !ok {
		return false
	}
	arn, _ := t.Attributes["targetGroupARN"].(string)
	if arn == "" {
		return false
	}
	tgid := model.ResourceID("aws:target-group:" + arn)
	for _, e := range g.Edges {
		if e.From == tgid && e.To == lb {
			return true
		}
	}
	return false
}

func neighbor(g *model.Graph, from model.ResourceID, k model.ResourceKind) model.ResourceID {
	for _, e := range g.Edges {
		if e.From == from {
			if r, ok := g.Nodes[e.To]; ok && r.Kind == k {
				return e.To
			}
		}
	}
	return ""
}
func strs(v any) []string { x, _ := v.([]string); return x }
func allowed(g *model.Graph, src, dst []string, t model.Resource, p int32) bool {
	ip, _ := t.Attributes["ip"].(string)
	for _, d := range dst {
		r, ok := g.Nodes[model.ResourceID("aws:sg:"+d)]
		if !ok {
			continue
		}
		for _, x := range r.Attributes["ingress"].([]model.SecurityGroupRule) {
			if x.Protocol != "-1" && x.Protocol != "tcp" {
				continue
			}
			if x.Protocol != "-1" && (p < x.FromPort || p > x.ToPort) {
				continue
			}
			for _, s := range x.SourceSGIDs {
				for _, a := range src {
					if s == a {
						return true
					}
				}
			}
			for _, c := range x.CIDRs {
				if _, n, e := net.ParseCIDR(c); e == nil && n.Contains(net.ParseIP(ip)) {
					return true
				}
			}
		}
	}
	return false
}
