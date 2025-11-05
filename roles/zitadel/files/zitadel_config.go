package main

import (
	"context"
	"log"
	"log/slog"
	"os"

	"github.com/zitadel/zitadel-go/v3/pkg/client"
	app "github.com/zitadel/zitadel-go/v3/pkg/client/zitadel/app/v2beta"
	"github.com/zitadel/zitadel-go/v3/pkg/zitadel"
)

func main() {
	domain := "zitadel.172.17.0.1.nip.io"
	token := "6YQZnz9sHSqCuWfPw620E3g3NqutTSXmEc_C1kBX6e4vuWTY2TD6DRPCks8Pn23g9ZQiaLo"

	ctx := context.Background()

	authOption := client.PAT(token)

	api, err := client.New(ctx, zitadel.New(domain, zitadel.WithPort(4443), zitadel.WithInsecureSkipVerifyTLS()), client.WithAuth(authOption))
	if err != nil {
		slog.Error("could not create api client", "error", err)
		os.Exit(1)
	}

	// resp, err := api.ManagementService().GetMyOrg(ctx, &management.GetMyOrgRequest{})
	// if err != nil {
	// 	slog.Error("gRPC call failed", "error", err)
	// 	os.Exit(1)
	// }

	resp, err := api.AppServiceV2Beta().CreateApplication(ctx, &app.CreateApplicationRequest{
		ProjectId: "345345430017671203",
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
}
