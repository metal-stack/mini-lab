package apitests

import (
	"bytes"
	"context"
	"fmt"
	"strings"

	apiv2 "github.com/metal-stack/api/go/metalstack/api/v2"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/remotecommand"
)

func generateApiServerToken(ctx context.Context, req *apiv2.TokenServiceCreateRequest) (string, error) {
	commands := generateTokenCommands(req)
	return execInPod(ctx, "metal-control-plane", "app=metal-apiserver", commands)
}

func execInPod(ctx context.Context, namespace, podSelector string, commands []string) (string, error) {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	configOverrides := &clientcmd.ConfigOverrides{}
	kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)
	restConfig, err := kubeConfig.ClientConfig()
	if err != nil {
		return "", err
	}

	clientset, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return "", err
	}

	podList, err := clientset.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{LabelSelector: podSelector})
	if err != nil {
		return "", err
	}
	if len(podList.Items) == 0 {
		return "", fmt.Errorf("no matching pod found")
	}

	pod := &podList.Items[0]

	fmt.Printf("pod:%s commands:%s", pod.Name, commands)

	req := clientset.CoreV1().RESTClient().Post().Resource("pods").Name(pod.Name).Namespace(pod.Namespace).SubResource("exec").VersionedParams(&corev1.PodExecOptions{
		Command: commands,
		Stdin:   false,
		Stdout:  true,
		Stderr:  true,
		TTY:     false,
	}, scheme.ParameterCodec)

	exec, err := remotecommand.NewSPDYExecutor(restConfig, "POST", req.URL())
	if err != nil {
		return "", err
	}

	var stdout, stderr bytes.Buffer
	err = exec.StreamWithContext(ctx, remotecommand.StreamOptions{
		Stdout: &stdout,
		Stderr: &stderr,
	})
	if err != nil {
		return "", err
	}

	if stderr.Len() > 0 {
		return "", fmt.Errorf("command failed: %s", stderr.String())
	}

	return strings.TrimSpace(stdout.String()), nil
}

func generateTokenCommands(req *apiv2.TokenServiceCreateRequest) []string {
	commands := []string{"/server", "token"}

	if req.Description != "" {
		commands = append(commands, "--description", req.Description)
	}
	if req.Expires != nil {
		commands = append(commands, "--expiration", req.Expires.AsDuration().String())
	}
	for _, perm := range req.Permissions {
		commands = append(commands, "--permissions", perm.Subject+"="+strings.Join(perm.Methods, ":"))
	}
	for project, role := range req.ProjectRoles {
		commands = append(commands, "--project-roles", project+"="+role.String())
	}
	for tenant, role := range req.TenantRoles {
		commands = append(commands, "--tenant-roles", tenant+"="+role.String())
	}
	if req.AdminRole != nil {
		commands = append(commands, "--admin-role", req.AdminRole.String())
	}
	if req.InfraRole != nil {
		// TODO not implemented in the apiserveer
		commands = append(commands, "--infra-role", req.InfraRole.String())
	}
	for machine, role := range req.MachineRoles {
		// TODO not implemented in the apiserveer
		commands = append(commands, "--machine-roles", machine+"="+role.String())
	}
	return commands
}
