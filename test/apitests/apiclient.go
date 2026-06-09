package apitests

import (
	"log/slog"
	"os"
	"testing"
	"time"

	apiv2client "github.com/metal-stack/api/go/client"
	apiv2 "github.com/metal-stack/api/go/metalstack/api/v2"
	metalgo "github.com/metal-stack/metal-go"
	"github.com/metal-stack/metal-go/api/client/version"
	"google.golang.org/protobuf/types/known/durationpb"

	"github.com/stretchr/testify/require"
)

func getV1Client(t *testing.T) metalgo.Client {
	var (
		metalURL   = os.Getenv("METALCTL_API_URL")
		metalHMAC  = os.Getenv("METALCTL_HMAC")
		metalToken = os.Getenv("METALCTL_TOKEN")
	)

	apiv1Client, err := metalgo.NewDriver(metalURL, metalToken, metalHMAC, metalgo.AuthType("Metal-Admin"))
	require.NoError(t, err)

	v, err := apiv1Client.Version().Info(&version.InfoParams{}, nil)
	require.NoError(t, err)
	t.Logf("connected to metal-api at:%s version:%s", metalURL, v.String())
	return apiv1Client
}

func getV2Client(t *testing.T, log *slog.Logger, tokenRoles *apiv2.TokenServiceCreateRequest) apiv2client.Client {
	var (
		metalApiV2URL = os.Getenv("METAL_APIV2_URL")
	)

	if tokenRoles == nil {
		tokenRoles = &apiv2.TokenServiceCreateRequest{
			Description: "api-conformance-tests",
			Expires:     durationpb.New(time.Hour),
			AdminRole:   apiv2.AdminRole_ADMIN_ROLE_EDITOR.Enum(),
		}
	}

	metalApiV2Token, err := generateApiServerToken(t.Context(), tokenRoles)
	require.NoError(t, err)

	apiv2Client, err := apiv2client.New(&apiv2client.DialConfig{
		BaseURL: metalApiV2URL,
		Token:   metalApiV2Token,
		Log:     log,
	})
	require.NoError(t, err)
	v2, err := apiv2Client.Apiv2().Version().Get(t.Context(), &apiv2.VersionServiceGetRequest{})
	require.NoError(t, err)
	t.Logf("connected to metal-apiserver at:%s version:%s", metalApiV2URL, v2.Version)

	return apiv2Client
}
