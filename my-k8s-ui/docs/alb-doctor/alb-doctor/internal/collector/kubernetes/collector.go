package kubernetes

import (
	"context"
	"fmt"
	"github.com/example/alb-doctor/internal/kubeapi"
	"github.com/example/alb-doctor/internal/model"
	discoveryv1 "k8s.io/api/discovery/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"time"
)

type Collector struct{ Kube *kubeapi.Client }

func New(k *kubeapi.Client) *Collector { return &Collector{k} }
func (c *Collector) Collect(ctx context.Context, ns, ingName string) (*model.Graph, error) {
	g := model.NewGraph()
	now := time.Now()
	ing, e := c.Kube.Kubernetes.NetworkingV1().Ingresses(ns).Get(ctx, ingName, metav1.GetOptions{})
	if e != nil {
		return nil, e
	}
	iid := model.ResourceID(fmt.Sprintf("k8s:ingress:%s/%s", ns, ingName))
	g.AddNode(model.Resource{ID: iid, Kind: model.KindIngress, Name: ingName, Namespace: ns})
	svcs := map[string]bool{}
	for _, r := range ing.Spec.Rules {
		if r.HTTP == nil {
			continue
		}
		for _, p := range r.HTTP.Paths {
			if p.Backend.Service != nil {
				svcs[p.Backend.Service.Name] = true
			}
		}
	}
	for sn := range svcs {
		sid := model.ResourceID(fmt.Sprintf("k8s:service:%s/%s", ns, sn))
		g.AddNode(model.Resource{ID: sid, Kind: model.KindService, Name: sn, Namespace: ns})
		g.AddEdge(model.Edge{From: iid, To: sid, Kind: model.EdgeRoutesTo, Confidence: 1, ObservedAt: now})
		slices, e := c.Kube.Kubernetes.DiscoveryV1().EndpointSlices(ns).List(ctx, metav1.ListOptions{LabelSelector: discoveryv1.LabelServiceName + "=" + sn})
		if e != nil {
			return nil, e
		}
		for _, es := range slices.Items {
			eid := model.ResourceID(fmt.Sprintf("k8s:endpointslice:%s/%s", ns, es.Name))
			g.AddNode(model.Resource{ID: eid, Kind: model.KindEndpointSlice, Name: es.Name, Namespace: ns})
			g.AddEdge(model.Edge{From: sid, To: eid, Kind: model.EdgeReferences, Confidence: 1, ObservedAt: now})
			for _, ep := range es.Endpoints {
				if ep.Conditions.Ready != nil && !*ep.Conditions.Ready {
					continue
				}
				for _, ip := range ep.Addresses {
					tid := model.ResourceID("target:ip:" + ip)
					g.AddNode(model.Resource{ID: tid, Kind: model.KindTarget, Name: ip, Attributes: map[string]any{"ip": ip}})
					g.AddEdge(model.Edge{From: eid, To: tid, Kind: model.EdgeReferences, Confidence: 1, ObservedAt: now})
					if ep.TargetRef != nil && ep.TargetRef.Kind == "Pod" {
						pid := model.ResourceID(fmt.Sprintf("k8s:pod:%s/%s", ns, ep.TargetRef.Name))
						g.AddNode(model.Resource{ID: pid, Kind: model.KindPod, Name: ep.TargetRef.Name, Namespace: ns})
						g.AddEdge(model.Edge{From: tid, To: pid, Kind: model.EdgeReferences, Confidence: 1, ObservedAt: now})
					}
				}
			}
		}
	}
	tgbs, e := c.Kube.ListTGB(ctx, ns)
	if e != nil {
		return nil, e
	}
	for _, t := range tgbs {
		name := t.GetName()
		id := model.ResourceID(fmt.Sprintf("k8s:tgb:%s/%s", ns, name))
		arn, _, _ := unstructured.NestedString(t.Object, "spec", "targetGroupARN")
		svc, _, _ := unstructured.NestedString(t.Object, "spec", "serviceRef", "name")
		g.AddNode(model.Resource{ID: id, Kind: model.KindTargetGroupBinding, Name: name, Namespace: ns, Attributes: map[string]any{"targetGroupARN": arn, "serviceName": svc}})
		if svc != "" {
			sid := model.ResourceID(fmt.Sprintf("k8s:service:%s/%s", ns, svc))
			if _, ok := g.Nodes[sid]; ok {
				g.AddEdge(model.Edge{From: id, To: sid, Kind: model.EdgeReferences, Confidence: 1, ObservedAt: now})
			}
		}
		if arn != "" {
			tid := model.ResourceID("aws:target-group:" + arn)
			g.AddNode(model.Resource{ID: tid, Kind: model.KindTargetGroup, Name: arn, Attributes: map[string]any{"arn": arn}})
			g.AddEdge(model.Edge{From: id, To: tid, Kind: model.EdgeReferences, Confidence: 1, ObservedAt: now})
		}
	}
	return g, nil
}
