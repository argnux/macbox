package main

import (
	"context"
	"macbox/internal/services"

	"macbox/pkg/network"
)

// App struct
type App struct {
	ctx     context.Context
	version string
	ns      services.INetworkService
}

// NewApp creates a new App application struct
func NewApp(v string) *App {
	return &App{
		version: v,
	}
}

func (a *App) GetAppVersion() string {
	return a.version
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	a.ns = services.NewNetworkService()

	go a.ns.StartLiveLoop(ctx)
}

func (a *App) CreateInterface(hardwarePortName string, newServiceName string) string {
	return a.ns.CreateInterface(hardwarePortName, newServiceName)
}

func (a *App) DeleteInterface(serviceName string) string {
	return a.ns.DeleteInterface(serviceName)
}

func (a *App) UpdateInterface(data network.UpdatePayload) string {
	return a.ns.UpdateInterface(data)
}

func (a *App) RegisterModels() network.HardwareInterface {
	return network.HardwareInterface{}
}
