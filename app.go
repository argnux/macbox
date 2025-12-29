package main

import (
	"context"
	"macbox/internal/services"
	"macbox/internal/tools"

	"macbox/pkg/network"
	"macbox/pkg/watcher"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// App struct
type App struct {
	ctx            context.Context
	version        string
	networkService *services.NetworkService
	updateService  *services.UpdateService
	watcherService *services.WatcherService

	pingTool *tools.PingTool
}

// NewApp creates a new App application struct
func NewApp(v string) *App {
	return &App{
		version:        v,
		networkService: services.NewNetworkService(),
		updateService:  services.NewUpdateService(v),
		watcherService: services.NewWatcherService(),
		pingTool:       tools.NewPingTool(),
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
	a.watcherService.SetContext(ctx)

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

func (a *App) RegisterUDPPacket() watcher.UDPPacket {
	return watcher.UDPPacket{}
}

func (a *App) CheckUpdate() *services.ReleaseInfo {
	return a.updateService.CheckForUpdates()
}

func (a *App) InstallUpdate(release *services.ReleaseInfo) string {
	return a.updateService.PerformUpdate(release)
}

func (a *App) StartPing(ip string, count int) string {
	err := a.pingTool.Start(a.ctx, ip, count, func(log string) {
		runtime.EventsEmit(a.ctx, "ping-log", log)
	})
	if err != nil {
		return err.Error()
	}

	return ""
}

func (a *App) StopPing() {
	a.pingTool.Stop()
}

func (a *App) GetAvailableParsers() []watcher.ParserMeta {
	return a.watcherService.GetAvailableParsers()
}

func (a *App) GetWatcherState() watcher.WatcherState {
	return a.watcherService.GetState()
}

func (a *App) SaveWatcherConfig(cfg watcher.WatcherConfig) {
	a.watcherService.SaveConfig(cfg)
}

func (a *App) StartWatcher() {
	a.watcherService.Start()
}

func (a *App) StopWatcher() {
	a.watcherService.Stop()
}
