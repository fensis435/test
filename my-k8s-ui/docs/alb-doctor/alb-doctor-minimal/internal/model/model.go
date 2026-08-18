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
	KindListener           ResourceKind = "Listener"
	KindListenerRule       ResourceKind = "ListenerRule"
	KindTargetGroup        ResourceKind = "TargetGroup"
	KindTarget             ResourceKind = "Target"
	KindSecurityGroup      ResourceKind = "SecurityGroup"
	KindNetworkInterface   ResourceKind = "NetworkInterface"
	KindSubnet             ResourceKind = "Subnet"
)

type ResourceID string

type TargetHealth struct {
	State       string
	Reason      string
	Description string
}

type SecurityGroupRule struct {
	Protocol    string
	FromPort    int32
	ToPort      int32
	CIDRs       []string
	SourceSGIDs []string
}

type SecurityGroup struct {
	ID      string
	Ingress []SecurityGroupRule
	Egress  []SecurityGroupRule
}

type Resource struct {
	ID         ResourceID
	Kind       ResourceKind
	Name       string
	Namespace  string
	Attributes map[string]any
}

type EvidenceSource string

const (
	SourceKubernetes EvidenceSource = "kubernetes"
	SourceAWS        EvidenceSource = "aws"
)

type Evidence struct {
	Source      EvidenceSource
	ResourceID  string
	Field       string
	Value       any
	Description string
	ObservedAt  time.Time
}

type EdgeKind string

const (
	EdgeRoutesTo   EdgeKind = "routes-to"
	EdgeReferences EdgeKind = "references"
	EdgeRegisters  EdgeKind = "registers"
	EdgeForwardsTo EdgeKind = "forwards-to"
	EdgeAttachedTo EdgeKind = "attached-to"
	EdgeLocatedIn  EdgeKind = "located-in"
)

type Edge struct {
	From       ResourceID
	To         ResourceID
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

func (g *Graph) Outgoing(id ResourceID, kind EdgeKind) []Edge {
	var out []Edge
	for _, e := range g.Edges {
		if e.From == id && (kind == "" || e.Kind == kind) {
			out = append(out, e)
		}
	}
	return out
}

type Severity string

const (
	SeverityInfo     Severity = "INFO"
	SeverityWarning  Severity = "WARNING"
	SeverityHigh     Severity = "HIGH"
	SeverityCritical Severity = "CRITICAL"
)

type Remediation struct {
	Description string
	Commands    []string
	Safe        bool
}

type Finding struct {
	ID          string
	Severity    Severity
	Title       string
	Summary     string
	RootCause   []ResourceID
	Evidence    []Evidence
	Remediation *Remediation
}
