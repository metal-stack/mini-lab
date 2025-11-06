package main

import (
	"context"
	"log"
	"log/slog"
	"os"

	"github.com/zitadel/zitadel-go/v3/pkg/client"
	app "github.com/zitadel/zitadel-go/v3/pkg/client/zitadel/app/v2beta"
	project "github.com/zitadel/zitadel-go/v3/pkg/client/zitadel/project/v2beta"
	"github.com/zitadel/zitadel-go/v3/pkg/zitadel"
)

func main() {
	domain := "zitadel.172.17.0.1.nip.io"
	token := os.Args[1]
	if token == "" {
		slog.Error("personal access token not provided")
		os.Exit(1)
	}

	ctx := context.Background()

	authOption := client.PAT(token)

	api, err := client.New(ctx, zitadel.New(domain, zitadel.WithPort(4443), zitadel.WithInsecureSkipVerifyTLS()), client.WithAuth(authOption))
	if err != nil {
		slog.Error("could not create api client", "error", err)
		os.Exit(1)
	}

	projectResp, err := api.ProjectServiceV2Beta().ListProjects(ctx, &project.ListProjectsRequest{})
	if err != nil {
		slog.Error("gRPC call failed", "error", err)
		os.Exit(1)
	}

	slog.Info("Projects", slog.Int("count", len(projectResp.Projects)))

	projectId := projectResp.Projects[0].Id

	resp, err := api.AppServiceV2Beta().CreateApplication(ctx, &app.CreateApplicationRequest{
		ProjectId: projectId,
		Name:      "metal-stack",
		Id:        "metal-stack",
		CreationRequestType: &app.CreateApplicationRequest_OidcRequest{
			OidcRequest: &app.CreateOIDCApplicationRequest{
				RedirectUris: []string{
					"http://v2.api.172.17.0.1.nip.io:8080/auth/openid-connect/callback",
				},
				ResponseTypes: []app.OIDCResponseType{
					app.OIDCResponseType_OIDC_RESPONSE_TYPE_CODE,
				},
				GrantTypes: []app.OIDCGrantType{
					app.OIDCGrantType_OIDC_GRANT_TYPE_AUTHORIZATION_CODE,
				},
				AppType:                app.OIDCAppType_OIDC_APP_TYPE_WEB,
				AuthMethodType:         app.OIDCAuthMethodType_OIDC_AUTH_METHOD_TYPE_POST,
				AccessTokenType:        app.OIDCTokenType_OIDC_TOKEN_TYPE_BEARER,
				Version:                app.OIDCVersion_OIDC_VERSION_1_0,
				PostLogoutRedirectUris: []string{},
				DevMode:                true,
			},
		},
	})
	if err != nil {
		slog.Error("gRPC call failed", "error", err)
		os.Exit(1)
	}

	log.Printf("Successfully called API: Your application is %s", resp.AppId)

	// Get client_id and client_secret
	log.Printf("Client ID: %s", resp.GetApiResponse().ClientId)
	log.Printf("Client Secret: %s", resp.GetApiResponse().ClientSecret)
}
