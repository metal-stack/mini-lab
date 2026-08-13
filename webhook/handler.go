package main

import (
	"context"
	"net/http"

	"gomodules.xyz/jsonpatch/v2"
	admissionv1 "k8s.io/api/admission/v1"
	v1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

type serviceMutator struct {
	decoder admission.Decoder
	targets []target
}

func (m *serviceMutator) Handle(ctx context.Context, req admission.Request) admission.Response {
	logger := log.FromContext(ctx).WithValues("namespace", req.Namespace, "name", req.Name)

	if req.Operation != admissionv1.Create && req.Operation != admissionv1.Update {
		return admission.Allowed("")
	}

	svc := &v1.Service{}
	if err := m.decoder.Decode(req, svc); err != nil {
		return admission.Errored(http.StatusBadRequest, err)
	}

	pinned, ok := m.matchingTarget(svc)
	if !ok {
		return admission.Allowed("not a target service")
	}

	if svc.Spec.LoadBalancerIP == pinned {
		return admission.Allowed("ip already pinned")
	}

	logger.Info("pinning loadBalancerIP", "operation", req.Operation, "loadBalancerIP", pinned, "old", svc.Spec.LoadBalancerIP)

	return admission.Patched("inject loadBalancerIP",
		jsonpatch.NewOperation("add", "/spec/loadBalancerIP", pinned))
}

func (m *serviceMutator) matchingTarget(svc *v1.Service) (string, bool) {
	if svc.Spec.Type != v1.ServiceTypeLoadBalancer {
		return "", false
	}
	for _, t := range m.targets {
		if svc.Namespace == t.namespace && svc.Name == t.name {
			return t.ip, true
		}
	}
	return "", false
}
