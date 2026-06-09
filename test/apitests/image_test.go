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
	"github.com/metal-stack/metal-go/api/client/image"
	"github.com/metal-stack/metal-go/api/models"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/testing/protocmp"
	"google.golang.org/protobuf/types/known/durationpb"
)

var (
	apiv2i1 = &apiv2.Image{
		Meta:        &apiv2.Meta{},
		Id:          "testimage-1.0.0",
		Url:         "https://images.metal-stack.io/metal-os/stable/debian/13/img.tar.lz4",
		Name:        new("Test Image"),
		Description: new("Test Image Description"),
		Features: []apiv2.ImageFeature{
			apiv2.ImageFeature_IMAGE_FEATURE_MACHINE,
		},
		Classification: apiv2.ImageClassification_IMAGE_CLASSIFICATION_SUPPORTED,
	}

	apiv1i1 = &models.V1ImageResponse{
		ID:             &apiv2i1.Id,
		URL:            apiv2i1.Url,
		Name:           *apiv2i1.Name,
		Description:    *apiv2i1.Description,
		Features:       []string{"machine"},
		Classification: "supported",
	}
)

func TestImage(t *testing.T) {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug}))
	v1Client := getV1Client(t)
	v2Client := getV2Client(t, log, &apiv2.TokenServiceCreateRequest{
		Description: "image-conformance-tests",
		Expires:     durationpb.New(1 * time.Minute),
		Permissions: []*apiv2.MethodPermission{
			{
				Subject: "*",
				Methods: []string{
					apiv2connect.ImageServiceGetProcedure,
					apiv2connect.VersionServiceGetProcedure,
					adminv2connect.ImageServiceCreateProcedure,
					adminv2connect.ImageServiceDeleteProcedure,
				},
			},
		},
	})

	deleteImageFn := func() {
		_, err := v1Client.Image().DeleteImage(&image.DeleteImageParams{ID: apiv2i1.Id}, nil)
		require.NoError(t, err)
	}

	defer func() {
		deleteImageFn()
	}()

	v1image, err := v1Client.Image().CreateImage(&image.CreateImageParams{
		Body: &models.V1ImageCreateRequest{
			ID:             &apiv2i1.Id,
			URL:            new(apiv2i1.Url),
			Name:           *apiv2i1.Name,
			Description:    *apiv2i1.Description,
			Features:       []string{"machine"},
			Classification: "supported",
		},
	}, nil)
	require.NoError(t, err)
	require.NotNil(t, v1image)

	resp, err := v2Client.Apiv2().Image().Get(t.Context(), &apiv2.ImageServiceGetRequest{Id: apiv2i1.Id})
	require.NoError(t, err)

	if diff := cmp.Diff(
		apiv2i1, resp.Image,
		protocmp.Transform(),
		protocmp.IgnoreFields(&apiv2.Meta{}, "created_at", "updated_at"),
		protocmp.IgnoreFields(&apiv2.Image{}, "expires_at"),
	); diff != "" {
		t.Errorf("image create and get () diff: %s", diff)
	}

	deleteImageFn()

	_, err = v2Client.Adminv2().Image().Create(t.Context(), &adminv2.ImageServiceCreateRequest{Image: apiv2i1})
	require.NoError(t, err)

	apiv1resp, err := v1Client.Image().FindImage(&image.FindImageParams{ID: *apiv1i1.ID}, nil)
	require.NoError(t, err)

	if diff := cmp.Diff(
		apiv1i1, apiv1resp.Payload,
		cmpopts.IgnoreFields(
			models.V1ImageResponse{}, "Changed", "Created", "ExpirationDate", "Usedby",
		),
	); diff != "" {
		t.Errorf("image create and get () diff: %s", diff)
	}
}
