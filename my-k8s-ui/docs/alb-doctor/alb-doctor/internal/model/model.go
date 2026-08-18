package model

import "time"

type ResourceKind string

const (
	KindIngress            ResourceKind = "Ingress"
	KindService            ResourceKind = "Service"
	KindEndpointSlice      ResourceKind = "EndpointSlice"
	KindPod                ResourceKind = "Pod"
	KindTargetGroupBinding ResourceKind = "TargetGroupBinding"
	KindLoadBalancer       ResourceKind = "LoadBalancer"
	KindTargetGroup        ResourceKind = "TargetGroup"
	KindTarget             ResourceKind = "Target"
	KindNetworkInterface   ResourceKind = "NetworkInterface"
	KindSecurityGroup      ResourceKind = "SecurityGroup"
)

type ResourceID string
type Resource struct {
	ID              ResourceID
	Kind            ResourceKind
	Name, Namespace string
	Attributes      map[string]any
}
type EdgeKind string

const (
	EdgeReferences EdgeKind = "references"
	EdgeRoutesTo   EdgeKind = "routes-to"
	EdgeForwardsTo EdgeKind = "forwards-to"
	EdgeAttachedTo EdgeKind = "attached-to"
)

type Evidence struct {
	Source, ResourceID, Field, Description string
	Value                                  any
	ObservedAt                             time.Time
}
type Edge struct {
	From, To   ResourceID
	Kind       EdgeKind
	Evidence   []Evidence
	Confidence float64
	ObservedAt time.Time
}
type Graph struct {
	Nodes map[ResourceID]Resource
	Edges []Edge
}

func NewGraph() *Graph              { return &Graph{Nodes: map[ResourceID]Resource{}} }
func (g *Graph) AddNode(r Resource) { g.Nodes[r.ID] = r }
func (g *Graph) AddEdge(e Edge)     { g.Edges = append(g.Edges, e) }

type TargetHealth struct{ State, Reason, Detail string }
type SecurityGroupRule struct {
	Protocol           string
	FromPort, ToPort   int32
	CIDRs, SourceSGIDs []string
}
type Severity string

const (
	SeverityInfo    Severity = "INFO"
	SeverityWarning Severity = "WARNING"
	SeverityHigh    Severity = "HIGH"
)

type Finding struct {
	ID             string
	Severity       Severity
	Title, Summary string
	RootCause      []ResourceID
	Evidence       []Evidence
}
