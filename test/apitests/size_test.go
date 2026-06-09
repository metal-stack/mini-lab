package apitests

import (
	"log/slog"
	"os"
	"testing"
	"time"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	adminv2 "github.com/metal-stack/api/go/metalstack/admin/v2"
	"github.com/metal-stack/api/go/metalstack/admin/v2/adminv2connect"
	apiv2 "github.com/metal-stack/api/go/metalstack/api/v2"
	"github.com/metal-stack/api/go/metalstack/api/v2/apiv2connect"
	"github.com/metal-stack/metal-go/api/client/size"
	"github.com/metal-stack/metal-go/api/models"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/testing/protocmp"
	"google.golang.org/protobuf/types/known/durationpb"
)

var (
	apiv2s1 = &apiv2.Size{
		Meta: &apiv2.Meta{
			Labels: &apiv2.Labels{
				Labels: map[string]string{
					"purpose": "integration-test",
				},
			},
		},
		Id:          "test-size",
		Name:        new("Test Size"),
		Description: new("Test Size Description"),
		Constraints: []*apiv2.SizeConstraint{
			{
				Type: apiv2.SizeConstraintType_SIZE_CONSTRAINT_TYPE_CORES,
				Min:  2,
				Max:  4,
			},
			{
				Type:       apiv2.SizeConstraintType_SIZE_CONSTRAINT_TYPE_GPU,
				Min:        1,
				Max:        2,
				Identifier: new("H100*"),
			},
			{
				Type: apiv2.SizeConstraintType_SIZE_CONSTRAINT_TYPE_MEMORY,
				Min:  4096,
				Max:  8192,
			},
			{
				Type:       apiv2.SizeConstraintType_SIZE_CONSTRAINT_TYPE_STORAGE,
				Min:        1024,
				Max:        2048,
				Identifier: new("/dev/sda*"),
			},
		},
	}

	apiv1s1 = &models.V1SizeResponse{
		ID:          &apiv2s1.Id,
		Name:        *apiv2s1.Name,
		Description: *apiv2s1.Description,
		Labels:      apiv2s1.Meta.Labels.Labels,
		Constraints: []*models.V1SizeConstraint{
			{
				Type: new("cores"),
				Min:  2,
				Max:  4,
			},
			{
				Type:       new("gpu"),
				Min:        1,
				Max:        2,
				Identifier: "H100*",
			},
			{
				Type: new("memory"),
				Min:  4096,
				Max:  8192,
			},
			{
				Type:       new("storage"),
				Min:        1024,
				Max:        2048,
				Identifier: "/dev/sda*",
			},
		},
	}
)

func TestSize(t *testing.T) {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug}))
	v1Client := getV1Client(t)
	v2Client := getV2Client(t, log, &apiv2.TokenServiceCreateRequest{
		Description: "size-conformance-tests",
		Expires:     durationpb.New(1 * time.Minute),
		Permissions: []*apiv2.MethodPermission{
			{
				Subject: "*",
				Methods: []string{
					apiv2connect.SizeServiceGetProcedure,
					apiv2connect.VersionServiceGetProcedure,
					adminv2connect.SizeServiceCreateProcedure,
					adminv2connect.SizeServiceDeleteProcedure,
				},
			},
		},
	})

	deleteSizeFn := func() {
		_, err := v1Client.Size().DeleteSize(&size.DeleteSizeParams{ID: apiv2s1.Id}, nil)
		require.NoError(t, err)
	}

	defer func() {
		deleteSizeFn()
	}()

	v1size, err := v1Client.Size().CreateSize(&size.CreateSizeParams{
		Body: &models.V1SizeCreateRequest{
			ID:          &apiv2s1.Id,
			Name:        *apiv2s1.Name,
			Description: *apiv2s1.Description,
			Labels:      apiv2s1.Meta.Labels.Labels,
			Constraints: apiv1s1.Constraints,
		},
	}, nil)
	require.NoError(t, err)
	require.NotNil(t, v1size)

	resp, err := v2Client.Apiv2().Size().Get(t.Context(), &apiv2.SizeServiceGetRequest{Id: apiv2s1.Id})
	require.NoError(t, err)

	if diff := cmp.Diff(
		apiv2s1, resp.Size,
		protocmp.Transform(),
		protocmp.IgnoreFields(
			&apiv2.Meta{}, "created_at", "updated_at",
		),
	); diff != "" {
		t.Errorf("size create and get () diff: %s", diff)
	}

	deleteSizeFn()

	_, err = v2Client.Adminv2().Size().Create(t.Context(), &adminv2.SizeServiceCreateRequest{Size: apiv2s1})
	require.NoError(t, err)

	apiv1resp, err := v1Client.Size().FindSize(&size.FindSizeParams{ID: *apiv1s1.ID}, nil)
	require.NoError(t, err)

	if diff := cmp.Diff(
		apiv1s1, apiv1resp.Payload,
		cmpopts.IgnoreFields(
			models.V1SizeResponse{}, "Changed", "Created",
		),
	); diff != "" {
		t.Errorf("size create and get () diff: %s", diff)
	}
}
