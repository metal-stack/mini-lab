package main

import (
	"context"
	"encoding/json"
	"testing"

	admissionv1 "k8s.io/api/admission/v1"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

func newTestMutator() *serviceMutator {
	scheme := runtime.NewScheme()
	_ = v1.AddToScheme(scheme)
	return &serviceMutator{
		decoder: admission.NewDecoder(scheme),
		targets: []target{
			{namespace: "virtual-garden-istio-ingress", name: "istio-ingressgateway", ip: "172.42.0.10"},
			{namespace: "istio-ingress", name: "istio-ingressgateway", ip: "172.42.0.11"},
		},
	}
}

func encodeService(t *testing.T, svc *v1.Service) []byte {
	t.Helper()
	b, err := json.Marshal(svc)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func req(t *testing.T, op admissionv1.Operation, svc *v1.Service) admission.Request {
	t.Helper()
	return admission.Request{AdmissionRequest: admissionv1.AdmissionRequest{
		Operation: op,
		Object:    runtime.RawExtension{Raw: encodeService(t, svc)},
	}}
}

func TestMutatesVirtualGardenWithoutIP(t *testing.T) {
	m := newTestMutator()
	svc := &v1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "istio-ingressgateway", Namespace: "virtual-garden-istio-ingress"},
		Spec:       v1.ServiceSpec{Type: v1.ServiceTypeLoadBalancer},
	}
	resp := m.Handle(context.Background(), req(t, admissionv1.Create, svc))
	if !resp.Allowed {
		t.Fatalf("expected allowed response, got %v", resp.Result)
	}
	if len(resp.Patches) != 1 {
		t.Fatalf("expected 1 patch, got %d", len(resp.Patches))
	}
	if resp.Patches[0].Path != "/spec/loadBalancerIP" || resp.Patches[0].Value != "172.42.0.10" {
		t.Fatalf("unexpected patch: %+v", resp.Patches[0])
	}
}

func TestMutatesIstioIngressWithoutIP(t *testing.T) {
	m := newTestMutator()
	svc := &v1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "istio-ingressgateway", Namespace: "istio-ingress"},
		Spec:       v1.ServiceSpec{Type: v1.ServiceTypeLoadBalancer},
	}
	resp := m.Handle(context.Background(), req(t, admissionv1.Create, svc))
	if !resp.Allowed {
		t.Fatalf("expected allowed response, got %v", resp.Result)
	}
	if len(resp.Patches) != 1 {
		t.Fatalf("expected 1 patch, got %d", len(resp.Patches))
	}
	if resp.Patches[0].Value != "172.42.0.11" {
		t.Fatalf("unexpected patch: %+v", resp.Patches[0])
	}
}

func TestDoesNotMutateAlreadyPinned(t *testing.T) {
	m := newTestMutator()
	svc := &v1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "istio-ingressgateway", Namespace: "virtual-garden-istio-ingress"},
		Spec:       v1.ServiceSpec{Type: v1.ServiceTypeLoadBalancer, LoadBalancerIP: "172.42.0.10"},
	}
	resp := m.Handle(context.Background(), req(t, admissionv1.Update, svc))
	if !resp.Allowed {
		t.Fatalf("expected allowed response, got %v", resp.Result)
	}
	if len(resp.Patches) != 0 {
		t.Fatalf("expected no patches, got %d", len(resp.Patches))
	}
}

func TestIgnoresOtherServices(t *testing.T) {
	m := newTestMutator()
	svc := &v1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "other", Namespace: "default"},
		Spec:       v1.ServiceSpec{Type: v1.ServiceTypeLoadBalancer},
	}
	resp := m.Handle(context.Background(), req(t, admissionv1.Create, svc))
	if !resp.Allowed || len(resp.Patches) != 0 {
		t.Fatalf("expected allowed with no patches, got %v patches=%d", resp.Result, len(resp.Patches))
	}
}

func TestParseTargets(t *testing.T) {
	got, err := parseTargets([]string{
		"virtual-garden-istio-ingress/istio-ingressgateway=172.42.0.10",
		"istio-ingress/istio-ingressgateway=172.42.0.11",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 targets, got %d", len(got))
	}
	if got[0].namespace != "virtual-garden-istio-ingress" || got[0].name != "istio-ingressgateway" || got[0].ip != "172.42.0.10" {
		t.Fatalf("unexpected target: %+v", got[0])
	}
}

func TestParseTargetsInvalid(t *testing.T) {
	if _, err := parseTargets([]string{"noequals"}); err == nil {
		t.Fatal("expected error for invalid target")
	}
}
