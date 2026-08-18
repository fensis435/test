package diagnostic

import (
	"context"
	"github.com/example/alb-doctor/internal/model"
)

type Rule interface {
	ID() string
	Evaluate(context.Context, *model.Graph) []model.Finding
}

type Engine struct{ rules []Rule }

func NewEngine(rules ...Rule) *Engine { return &Engine{rules: rules} }
func (e *Engine) Run(ctx context.Context, g *model.Graph) []model.Finding {
	var findings []model.Finding
	for _, r := range e.rules {
		findings = append(findings, r.Evaluate(ctx, g)...)
	}
	return findings
}
