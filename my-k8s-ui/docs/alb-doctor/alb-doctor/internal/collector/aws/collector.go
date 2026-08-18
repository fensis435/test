package awscollector

import (
	"context"
	"fmt"
	"net"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	elbtypes "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2/types"
	"github.com/example/alb-doctor/internal/model"
)

type ELB interface {
	DescribeLoadBalancers(context.Context, *elasticloadbalancingv2.DescribeLoadBalancersInput, ...func(*elasticloadbalancingv2.Options)) (*elasticloadbalancingv2.DescribeLoadBalancersOutput, error)
	DescribeTargetGroups(context.Context, *elasticloadbalancingv2.DescribeTargetGroupsInput, ...func(*elasticloadbalancingv2.Options)) (*elasticloadbalancingv2.DescribeTargetGroupsOutput, error)
	DescribeTargetHealth(context.Context, *elasticloadbalancingv2.DescribeTargetHealthInput, ...func(*elasticloadbalancingv2.Options)) (*elasticloadbalancingv2.DescribeTargetHealthOutput, error)
	DescribeListeners(context.Context, *elasticloadbalancingv2.DescribeListenersInput, ...func(*elasticloadbalancingv2.Options)) (*elasticloadbalancingv2.DescribeListenersOutput, error)
	DescribeRules(context.Context, *elasticloadbalancingv2.DescribeRulesInput, ...func(*elasticloadbalancingv2.Options)) (*elasticloadbalancingv2.DescribeRulesOutput, error)
}

type EC2 interface {
	DescribeNetworkInterfaces(context.Context, *ec2.DescribeNetworkInterfacesInput, ...func(*ec2.Options)) (*ec2.DescribeNetworkInterfacesOutput, error)
	DescribeSecurityGroups(context.Context, *ec2.DescribeSecurityGroupsInput, ...func(*ec2.Options)) (*ec2.DescribeSecurityGroupsOutput, error)
}

type Collector struct {
	ELB ELB
	EC2 EC2
}

func New(e ELB, c EC2) *Collector { return &Collector{ELB: e, EC2: c} }

func (c *Collector) Collect(ctx context.Context, g *model.Graph) error {
	for id, r := range g.Nodes {
		if r.Kind != model.KindTargetGroup {
			continue
		}
		arn, _ := r.Attributes["arn"].(string)
		out, err := c.ELB.DescribeTargetGroups(ctx, &elasticloadbalancingv2.DescribeTargetGroupsInput{TargetGroupArns: []string{arn}})
		if err != nil {
			return fmt.Errorf("describe target group %s: %w", arn, err)
		}
		if len(out.TargetGroups) == 0 {
			continue
		}
		tg := out.TargetGroups[0]
		port := aws.ToInt32(tg.Port)
		r.Attributes["port"] = port
		r.Attributes["protocol"] = string(tg.Protocol)
		r.Attributes["targetType"] = string(tg.TargetType)
		g.Nodes[id] = r

		th, err := c.ELB.DescribeTargetHealth(ctx, &elasticloadbalancingv2.DescribeTargetHealthInput{TargetGroupArn: &arn})
		if err != nil {
			return fmt.Errorf("describe target health %s: %w", arn, err)
		}
		for _, d := range th.TargetHealthDescriptions {
			if d.Target == nil || d.Target.Id == nil {
				continue
			}
			ip := *d.Target.Id
			tid := model.ResourceID("aws:target:" + arn + ":" + ip)
			if _, ok := g.Nodes[tid]; !ok {
				g.AddNode(model.Resource{ID: tid, Kind: model.KindTarget, Name: ip, Attributes: map[string]any{"ip": ip, "awsTarget": true}})
			}
			n := g.Nodes[tid]
			n.Attributes["port"] = port
			n.Attributes["health"] = model.TargetHealth{State: string(d.TargetHealth.State), Reason: string(d.TargetHealth.Reason), Detail: aws.ToString(d.TargetHealth.Description)}
			n.Attributes["targetGroupARN"] = arn
			g.Nodes[tid] = n
			g.AddEdge(model.Edge{From: id, To: tid, Kind: model.EdgeForwardsTo, Confidence: 1})

			if net.ParseIP(ip) == nil {
				continue
			}
			eni, err := c.findENI(ctx, ip)
			if err != nil {
				return err
			}
			if eni == nil {
				continue
			}
			eid := model.ResourceID("aws:eni:" + aws.ToString(eni.NetworkInterfaceId))
			sgids := []string{}
			for _, x := range eni.Groups {
				if x.GroupId != nil {
					sgids = append(sgids, *x.GroupId)
				}
			}
			g.AddNode(model.Resource{ID: eid, Kind: model.KindNetworkInterface, Name: aws.ToString(eni.NetworkInterfaceId), Attributes: map[string]any{"securityGroupIDs": sgids, "privateIP": ip}})
			g.AddEdge(model.Edge{From: tid, To: eid, Kind: model.EdgeAttachedTo, Confidence: 1})
			for _, sg := range sgids {
				if err := c.addSG(ctx, g, sg); err != nil {
					return err
				}
				g.AddEdge(model.Edge{From: eid, To: model.ResourceID("aws:sg:" + sg), Kind: model.EdgeAttachedTo, Confidence: 1})
			}
		}
	}

	lbs, err := c.ELB.DescribeLoadBalancers(ctx, &elasticloadbalancingv2.DescribeLoadBalancersInput{})
	if err != nil {
		return err
	}
	for _, lb := range lbs.LoadBalancers {
		if lb.LoadBalancerArn == nil || lb.Type != "application" {
			continue
		}
		lbid := model.ResourceID("aws:load-balancer:" + *lb.LoadBalancerArn)
		sgs := append([]string(nil), lb.SecurityGroups...)
		g.AddNode(model.Resource{ID: lbid, Kind: model.KindLoadBalancer, Name: aws.ToString(lb.LoadBalancerName), Attributes: map[string]any{"securityGroupIDs": sgs, "arn": *lb.LoadBalancerArn}})
		for _, sg := range sgs {
			if err := c.addSG(ctx, g, sg); err != nil {
				return err
			}
			g.AddEdge(model.Edge{From: lbid, To: model.ResourceID("aws:sg:" + sg), Kind: model.EdgeAttachedTo, Confidence: 1})
		}
		listeners, err := c.ELB.DescribeListeners(ctx, &elasticloadbalancingv2.DescribeListenersInput{LoadBalancerArn: lb.LoadBalancerArn})
		if err != nil {
			return err
		}
		for _, lis := range listeners.Listeners {
			if lis.ListenerArn == nil {
				continue
			}
			rules, err := c.ELB.DescribeRules(ctx, &elasticloadbalancingv2.DescribeRulesInput{ListenerArn: lis.ListenerArn})
			if err != nil {
				return err
			}
			for _, rule := range rules.Rules {
				for _, arn := range actionTargetGroups(rule.Actions) {
					tgid := model.ResourceID("aws:target-group:" + arn)
					if _, ok := g.Nodes[tgid]; ok {
						g.AddEdge(model.Edge{From: tgid, To: lbid, Kind: model.EdgeForwardsTo, Confidence: 1})
					}
				}
			}
		}
	}
	return nil
}

func actionTargetGroups(actions []elbtypes.Action) []string {
	var out []string
	for _, a := range actions {
		if a.TargetGroupArn != nil {
			out = append(out, *a.TargetGroupArn)
		}
		if a.ForwardConfig != nil {
			for _, tg := range a.ForwardConfig.TargetGroups {
				if tg.TargetGroupArn != nil {
					out = append(out, *tg.TargetGroupArn)
				}
			}
		}
	}
	return out
}

func (c *Collector) findENI(ctx context.Context, ip string) (*ec2types.NetworkInterface, error) {
	o, err := c.EC2.DescribeNetworkInterfaces(ctx, &ec2.DescribeNetworkInterfacesInput{Filters: []ec2types.Filter{{Name: aws.String("private-ip-address"), Values: []string{ip}}}})
	if err != nil {
		return nil, fmt.Errorf("find ENI %s: %w", ip, err)
	}
	if len(o.NetworkInterfaces) == 0 {
		return nil, nil
	}
	return &o.NetworkInterfaces[0], nil
}

func (c *Collector) addSG(ctx context.Context, g *model.Graph, id string) error {
	rid := model.ResourceID("aws:sg:" + id)
	if _, ok := g.Nodes[rid]; ok {
		return nil
	}
	o, err := c.EC2.DescribeSecurityGroups(ctx, &ec2.DescribeSecurityGroupsInput{GroupIds: []string{id}})
	if err != nil {
		return fmt.Errorf("describe SG %s: %w", id, err)
	}
	if len(o.SecurityGroups) == 0 {
		return nil
	}
	s := o.SecurityGroups[0]
	rules := []model.SecurityGroupRule{}
	for _, p := range s.IpPermissions {
		r := model.SecurityGroupRule{Protocol: strings.ToLower(aws.ToString(p.IpProtocol)), FromPort: aws.ToInt32(p.FromPort), ToPort: aws.ToInt32(p.ToPort)}
		for _, x := range p.IpRanges {
			if x.CidrIp != nil {
				r.CIDRs = append(r.CIDRs, *x.CidrIp)
			}
		}
		for _, x := range p.UserIdGroupPairs {
			if x.GroupId != nil {
				r.SourceSGIDs = append(r.SourceSGIDs, *x.GroupId)
			}
		}
		rules = append(rules, r)
	}
	g.AddNode(model.Resource{ID: rid, Kind: model.KindSecurityGroup, Name: aws.ToString(s.GroupName), Attributes: map[string]any{"groupID": id, "ingress": rules}})
	return nil
}
