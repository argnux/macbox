package services

import (
	"context"
	"macbox/pkg/network"
)

type Mode int

const (
	ManualMode Mode = 1 << 0
	DHCPMode   Mode = 1 << 1
)

type INetworkService interface {
	StartLiveLoop(ctx context.Context)

	CreateInterface(hardwarePortName string, newServiceName string) string
	DeleteInterface(serviceName string) string
	UpdateInterface(data network.UpdatePayload) string
}
