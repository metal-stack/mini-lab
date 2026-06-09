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
	"github.com/metal-stack/metal-go/api/client/partition"
	"github.com/metal-stack/metal-go/api/models"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/testing/protocmp"
	"google.golang.org/protobuf/types/known/durationpb"
)

var (
	apiv2p1 = &apiv2.Partition{
		Meta: &apiv2.Meta{
			Labels: &apiv2.Labels{
				Labels: map[string]string{
					"purpose": "integration-test",
				},
			},
		},
		Id:                   "test-partition",
		Description:          "Test Partition",
		MgmtServiceAddresses: []string{"mgmt.test.partition"},
		BootConfiguration: &apiv2.PartitionBootConfiguration{
			Commandline: "a commandline",
			ImageUrl:    "https://1.1.1.1",
			KernelUrl:   "https://1.1.1.1",
		},
		DnsServers: []*apiv2.DNSServer{
			{Ip: "1.1.1.1"},
		},
		NtpServers: []*apiv2.NTPServer{
			{Address: "pool1.ntp.org"},
		},
	}

	apiv1p1 = &models.V1PartitionResponse{
		ID:                 &apiv2p1.Id,
		Name:               apiv2p1.Id,
		Description:        apiv2p1.Description,
		Mgmtserviceaddress: apiv2p1.MgmtServiceAddresses[0],
		Bootconfig: &models.V1PartitionBootConfiguration{
			Commandline: apiv2p1.BootConfiguration.Commandline,
			Imageurl:    apiv2p1.BootConfiguration.ImageUrl,
			Kernelurl:   apiv2p1.BootConfiguration.KernelUrl,
		},
		DNSServers: []*models.V1DNSServer{
			{IP: &apiv2p1.DnsServers[0].Ip},
		},
		NtpServers: []*models.V1NTPServer{
			{Address: &apiv2p1.NtpServers[0].Address},
		},
		Labels: apiv2p1.Meta.Labels.Labels,
	}
)

func TestPartition(t *testing.T) {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug}))
	v1Client := getV1Client(t)
	v2Client := getV2Client(t, log, &apiv2.TokenServiceCreateRequest{
		Description: "partition-conformance-tests",
		Expires:     durationpb.New(1 * time.Minute),
		Permissions: []*apiv2.MethodPermission{
			{
				Subject: "*",
				Methods: []string{
					apiv2connect.PartitionServiceGetProcedure,
					apiv2connect.VersionServiceGetProcedure,
					adminv2connect.PartitionServiceCreateProcedure,
				},
			},
		},
	})

	deletePartitionFn := func() {
		_, err := v1Client.Partition().DeletePartition(&partition.DeletePartitionParams{ID: apiv2p1.Id}, nil)
		require.NoError(t, err)
	}

	defer func() {
		deletePartitionFn()
	}()

	v1partition, err := v1Client.Partition().CreatePartition(&partition.CreatePartitionParams{
		Body: &models.V1PartitionCreateRequest{
			Bootconfig: &models.V1PartitionBootConfiguration{
				Commandline: apiv2p1.BootConfiguration.Commandline,
				Imageurl:    apiv2p1.BootConfiguration.ImageUrl,
				Kernelurl:   apiv2p1.BootConfiguration.KernelUrl,
			},
			Description:        apiv2p1.Description,
			ID:                 new(apiv2p1.Id),
			Mgmtserviceaddress: apiv2p1.MgmtServiceAddresses[0],
			DNSServers: []*models.V1DNSServer{
				{IP: &apiv2p1.DnsServers[0].Ip},
			},
			NtpServers: []*models.V1NTPServer{
				{Address: &apiv2p1.NtpServers[0].Address},
			},
			Labels: apiv2p1.Meta.Labels.Labels,
		},
	}, nil)
	require.NoError(t, err)
	require.NotNil(t, v1partition)

	resp, err := v2Client.Apiv2().Partition().Get(t.Context(), &apiv2.PartitionServiceGetRequest{Id: apiv2p1.Id})
	require.NoError(t, err)

	if diff := cmp.Diff(
		apiv2p1, resp.Partition,
		protocmp.Transform(),
		protocmp.IgnoreFields(
			&apiv2.Meta{}, "created_at", "updated_at",
		),
	); diff != "" {
		t.Errorf("partition create and get () diff: %s", diff)
	}

	deletePartitionFn()

	_, err = v2Client.Adminv2().Partition().Create(t.Context(), &adminv2.PartitionServiceCreateRequest{Partition: apiv2p1})
	require.NoError(t, err)

	apiv1resp, err := v1Client.Partition().FindPartition(&partition.FindPartitionParams{ID: *apiv1p1.ID}, nil)
	require.NoError(t, err)

	if diff := cmp.Diff(
		apiv1p1, apiv1resp.Payload,
		cmpopts.IgnoreFields(
			models.V1PartitionResponse{}, "Changed", "Created",
		),
	); diff != "" {
		t.Errorf("partition create and get () diff: %s", diff)
	}
}
