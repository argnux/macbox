package main

import (
	"context"
	"macbox/internal/services"

	"macbox/pkg/network"
)

// App struct
type App struct {
	ctx            context.Context
	version        string
	networkService *services.NetworkService
	updateService  *services.UpdateService
}

// NewApp creates a new App application struct
func NewApp(v string) *App {
	return &App{
		version:        v,
		networkService: services.NewNetworkService(),
		updateService:  services.NewUpdateService(v),
	}
}

func (a *App) GetAppVersion() string {
	return a.version
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	a.updateService.SetContext(ctx)

	go a.networkService.StartLiveLoop(ctx)
}

func (a *App) CreateInterface(hardwarePortName string, newServiceName string) string {
	return a.networkService.CreateInterface(hardwarePortName, newServiceName)
}

func (a *App) DeleteInterface(serviceName string) string {
	return a.networkService.DeleteInterface(serviceName)
}

func (a *App) UpdateInterface(data network.UpdatePayload) string {
	return a.networkService.UpdateInterface(data)
}

func (a *App) RegisterModels() network.HardwareInterface {
	return network.HardwareInterface{}
}

func (a *App) CheckUpdate() *services.ReleaseInfo {
	return a.updateService.CheckForUpdates()
}

func (a *App) InstallUpdate(release *services.ReleaseInfo) string {
	return a.updateService.PerformUpdate(release)
}
