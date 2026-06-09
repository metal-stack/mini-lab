package apitests

import (
	"testing"
	"time"

	apiv2 "github.com/metal-stack/api/go/metalstack/api/v2"
	"github.com/metal-stack/api/go/metalstack/api/v2/apiv2connect"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/durationpb"
)

func TestGenerateTokenCommand(t *testing.T) {
	tests := []struct {
		name string
		req  *apiv2.TokenServiceCreateRequest
		want []string
	}{
		{
			name: "minimal - description only",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "test-token",
			},
			want: []string{"/server", "token", "--description", "test-token"},
		},
		{
			name: "empty description",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "",
			},
			want: []string{"/server", "token"},
		},
		{
			name: "with expiration",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "expiring-token",
				Expires:     durationpb.New(90 * time.Minute),
			},
			want: []string{"/server", "token", "--description", "expiring-token", "--expiration", "1h30m0s"},
		},
		{
			name: "with permissions",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "perm-token",
				Permissions: []*apiv2.MethodPermission{
					{
						Subject: "*",
						Methods: []string{
							apiv2connect.TokenServiceGetProcedure,
							apiv2connect.TokenServiceListProcedure,
						},
					},
					{
						Subject: "project-id-1",
						Methods: []string{apiv2connect.ProjectServiceGetProcedure}},
				},
			},
			want: []string{"/server", "token", "--description", "perm-token",
				"--permissions", "*=/metalstack.api.v2.TokenService/Get:/metalstack.api.v2.TokenService/List",
				"--permissions", "project-id-1=/metalstack.api.v2.ProjectService/Get",
			},
		},
		{
			name: "with project roles",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "project-role-token",
				ProjectRoles: map[string]apiv2.ProjectRole{
					"p1": apiv2.ProjectRole_PROJECT_ROLE_OWNER,
					"p2": apiv2.ProjectRole_PROJECT_ROLE_VIEWER,
				},
			},
			want: []string{"/server", "token", "--description", "project-role-token",
				"--project-roles", "p1=PROJECT_ROLE_OWNER",
				"--project-roles", "p2=PROJECT_ROLE_VIEWER",
			},
		},
		{
			name: "with tenant roles",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "tenant-role-token",
				TenantRoles: map[string]apiv2.TenantRole{
					"t1": apiv2.TenantRole_TENANT_ROLE_EDITOR,
				},
			},
			want: []string{"/server", "token", "--description", "tenant-role-token",
				"--tenant-roles", "t1=TENANT_ROLE_EDITOR",
			},
		},
		{
			name: "with admin role",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "admin-token",
				AdminRole:   apiv2.AdminRole_ADMIN_ROLE_EDITOR.Enum(),
			},
			want: []string{"/server", "token", "--description", "admin-token",
				"--admin-role", "ADMIN_ROLE_EDITOR",
			},
		},
		{
			name: "with infra role",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "infra-token",
				InfraRole:   apiv2.InfraRole_INFRA_ROLE_EDITOR.Enum(),
			},
			want: []string{"/server", "token", "--description", "infra-token",
				"--infra-role", "INFRA_ROLE_EDITOR",
			},
		},
		{
			name: "with machine roles",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "machine-token",
				MachineRoles: map[string]apiv2.MachineRole{
					"m1": apiv2.MachineRole_MACHINE_ROLE_EDITOR,
					"m2": apiv2.MachineRole_MACHINE_ROLE_VIEWER,
				},
			},
			want: []string{"/server", "token", "--description", "machine-token",
				"--machine-roles", "m1=MACHINE_ROLE_EDITOR",
				"--machine-roles", "m2=MACHINE_ROLE_VIEWER",
			},
		},
		{
			name: "all fields",
			req: &apiv2.TokenServiceCreateRequest{
				Description: "full-token",
				Expires:     durationpb.New(30 * time.Minute),
				Permissions: []*apiv2.MethodPermission{
					{Subject: "*", Methods: []string{apiv2connect.ImageServiceGetProcedure}},
				},
				ProjectRoles: map[string]apiv2.ProjectRole{
					"prj-1": apiv2.ProjectRole_PROJECT_ROLE_EDITOR,
				},
				TenantRoles: map[string]apiv2.TenantRole{
					"tnt-1": apiv2.TenantRole_TENANT_ROLE_OWNER,
				},
				AdminRole: apiv2.AdminRole_ADMIN_ROLE_VIEWER.Enum(),
				InfraRole: apiv2.InfraRole_INFRA_ROLE_VIEWER.Enum(),
				MachineRoles: map[string]apiv2.MachineRole{
					"mc-1": apiv2.MachineRole_MACHINE_ROLE_EDITOR,
				},
			},
			want: []string{"/server", "token", "--description", "full-token",
				"--expiration", "30m0s",
				"--permissions", "*=/metalstack.api.v2.ImageService/Get",
				"--project-roles", "prj-1=PROJECT_ROLE_EDITOR",
				"--tenant-roles", "tnt-1=TENANT_ROLE_OWNER",
				"--admin-role", "ADMIN_ROLE_VIEWER",
				"--infra-role", "INFRA_ROLE_VIEWER",
				"--machine-roles", "mc-1=MACHINE_ROLE_EDITOR",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := generateTokenCommands(tt.req)
			require.ElementsMatch(t, tt.want, got)
		})
	}
}
