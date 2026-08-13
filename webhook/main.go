package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/go-logr/logr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

type target struct {
	namespace string
	name      string
	ip        string
}

func main() {
	var certDir, webhookHost string
	var webhookPort int
	targetFlags := stringSliceFlag{}
	flag.Var(&targetFlags, "target", "LoadBalancer service to pin, in the form namespace/name=ip. May be repeated.")
	flag.StringVar(&certDir, "cert-dir", "/certs", "The directory that contains the server key and certificate.")
	flag.StringVar(&webhookHost, "webhook-host", "", "The host the webhook server binds to.")
	flag.IntVar(&webhookPort, "webhook-port", 9443, "The port the webhook server binds to.")
	flag.Parse()

	slogLogger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	log.SetLogger(logr.FromSlogHandler(slogLogger.Handler()))

	targets, err := parseTargets(targetFlags.values)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid target: %v\n", err)
		os.Exit(1)
	}
	if len(targets) == 0 {
		fmt.Fprintln(os.Stderr, "at least one --target is required")
		os.Exit(1)
	}

	ctx := context.Background()

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), manager.Options{
		WebhookServer: webhook.NewServer(webhook.Options{
			Host:    webhookHost,
			Port:    webhookPort,
			CertDir: certDir,
		}),
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "unable to set up manager: %v\n", err)
		os.Exit(1)
	}

	decoder := admission.NewDecoder(mgr.GetScheme())

	mgr.GetWebhookServer().Register("/mutate-services", &webhook.Admission{
		Handler: &serviceMutator{
			decoder: decoder,
			targets: targets,
		},
	})

	if err := mgr.Start(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "problem running manager: %v\n", err)
		os.Exit(1)
	}
}

type stringSliceFlag struct {
	values []string
}

func (s *stringSliceFlag) String() string {
	return strings.Join(s.values, ",")
}

func (s *stringSliceFlag) Set(value string) error {
	s.values = append(s.values, value)
	return nil
}

func parseTargets(values []string) ([]target, error) {
	var targets []target
	for _, v := range values {
		parts := strings.SplitN(v, "=", 2)
		if len(parts) != 2 {
			return nil, fmt.Errorf("expected namespace/name=ip, got %q", v)
		}
		nsName := strings.SplitN(parts[0], "/", 2)
		if len(nsName) != 2 {
			return nil, fmt.Errorf("expected namespace/name=ip, got %q", v)
		}
		targets = append(targets, target{
			namespace: nsName[0],
			name:      nsName[1],
			ip:        parts[1],
		})
	}
	return targets, nil
}
