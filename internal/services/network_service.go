package services

import (
	"context"
	"macbox/pkg/network"
)

type INetworkService interface {
	StartLiveLoop(ctx context.Context)

	CreateInterface(hardwarePortName string, newServiceName string) string
	DeleteInterface(serviceName string) string
	UpdateInterface(data network.UpdatePayload) string
}
