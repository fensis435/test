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

func NewClient(kubeconfig string) (*Client, error) {
	cfg, err := clientcmd.BuildConfigFromFlags("", filepath.Clean(kubeconfig))
	if err != nil {
		return nil, err
	}
	k, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	d, err := dynamic.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	return &Client{Kubernetes: k, Dynamic: d}, nil
}

var tgbGVR = schema.GroupVersionResource{Group: "elbv2.k8s.aws", Version: "v1beta1", Resource: "targetgroupbindings"}

func (c *Client) ListTGB(ctx context.Context, namespace string) ([]unstructured.Unstructured, error) {
	l, err := c.Dynamic.Resource(tgbGVR).Namespace(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	return l.Items, nil
}
