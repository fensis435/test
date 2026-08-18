package collector

import (
	"context"
	"github.com/example/alb-doctor/internal/model"
)

type Collector interface {
	Collect(context.Context) ([]model.Resource, []model.Edge, error)
}
