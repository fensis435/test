package kubeapi

import (
	"context"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"path/filepath"
)

type Client struct {
	Kubernetes kubernetes.Interface
	Dynamic    dynamic.Interface
}

var TGBGVR = schema.GroupVersionResource{Group: "elbv2.k8s.aws", Version: "v1beta1", Resource: "targetgroupbindings"}

func NewClient(kubeconfig string) (*Client, error) {
	cfg, e := clientcmd.BuildConfigFromFlags("", filepath.Clean(kubeconfig))
	if e != nil {
		return nil, e
	}
	k, e := kubernetes.NewForConfig(cfg)
	if e != nil {
		return nil, e
	}
	d, e := dynamic.NewForConfig(cfg)
	if e != nil {
		return nil, e
	}
	return &Client{k, d}, nil
}
func (c *Client) ListTGB(ctx context.Context, ns string) ([]unstructured.Unstructured, error) {
	x, e := c.Dynamic.Resource(TGBGVR).Namespace(ns).List(ctx, metav1.ListOptions{})
	if e != nil {
		return nil, e
	}
	return x.Items, nil
}
