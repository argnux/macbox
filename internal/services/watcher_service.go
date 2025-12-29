package services

import (
	"context"
	"fmt"
	"macbox/internal/parsers"
	"macbox/pkg/watcher"
	"net"
	"sync"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

type WatcherService struct {
	ctx           context.Context
	cancelFunc    context.CancelFunc
	state         watcher.WatcherState
	mu            sync.Mutex
	parsersList   []watcher.ProtocolParser
	parsersMap    map[string]watcher.ProtocolParser
	currentParser watcher.ProtocolParser
}

func NewWatcherService() *WatcherService {
	service := &WatcherService{
		state: watcher.WatcherState{
			Config: watcher.WatcherConfig{
				Protocol: "udp",
				Port:     8080,
			},
		},
		parsersMap: make(map[string]watcher.ProtocolParser),
	}
	service.registerParser(&parsers.RawParser{})
	service.registerParser(&parsers.MavlinkParser{})

	service.currentParser = service.parsersList[0]
	service.state.Config.Parser = service.currentParser.ID()

	return service
}

func (w *WatcherService) registerParser(p watcher.ProtocolParser) {
	w.parsersList = append(w.parsersList, p)
	w.parsersMap[p.ID()] = p
}

func (w *WatcherService) SetContext(ctx context.Context) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.ctx = ctx
}

func (w *WatcherService) GetAvailableParsers() []watcher.ParserMeta {
	var meta []watcher.ParserMeta

	for _, p := range w.parsersList {
		meta = append(meta, watcher.ParserMeta{
			ID:          p.ID(),
			Name:        p.Name(),
			Description: p.Description(),
		})
	}

	return meta
}

func (w *WatcherService) SetParser(id string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if p, ok := w.parsersMap[id]; ok {
		w.currentParser = p
	}
}

func (w *WatcherService) GetState() watcher.WatcherState {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.state
}

func (w *WatcherService) SaveConfig(cfg watcher.WatcherConfig) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.state.Config = cfg
}

func udpReceiver(conn *net.UDPConn, dataChan chan watcher.UDPPacket, errChan chan error) {
	buffer := make([]byte, 1024)
	for {
		n, from, err := conn.ReadFromUDP(buffer)
		if err != nil {
			errChan <- err
			return
		}

		toSend := append([]byte(nil), buffer[:n]...)

		packet := watcher.UDPPacket{
			Timestamp: time.Now(),
			Size:      n,
			Payload:   toSend,
			FromIP:    from.String(),
		}

		dataChan <- packet
	}
}

func (w *WatcherService) Start() {
	ctx, cancel := context.WithCancel(w.ctx)
	w.SetParser(w.state.Config.Parser)

	w.mu.Lock()
	w.cancelFunc = cancel
	w.state.IsRunning = true
	parser := w.currentParser
	w.mu.Unlock()

	go func() {
		var id int64 = 0

		addr, err := net.ResolveUDPAddr("udp", fmt.Sprintf(":%d", w.state.Config.Port))
		if err != nil {
			fmt.Println(err)
		}
		conn, err := net.ListenUDP("udp", addr)
		if err != nil {
			fmt.Println(err)
		}
		defer conn.Close()

		dataChan := make(chan watcher.UDPPacket)
		errChan := make(chan error)

		go udpReceiver(conn, dataChan, errChan)

		for {
			select {
			case <-ctx.Done():
				return
			case packet := <-dataChan:
				packet.ID = id
				packet.Protocol = w.state.Config.Protocol
				packet.Parser = w.state.Config.Parser
				packet.Port = w.state.Config.Port
				packet.ParsedData, _ = parser.Parse(packet.Payload)

				runtime.EventsEmit(w.ctx, "packet_received", packet)
				id++
			case err := <-errChan:
				fmt.Printf("Error in receiver: %v\n", err)
				return
			}
		}
	}()
}

func (w *WatcherService) Stop() {
	w.mu.Lock()
	defer w.mu.Unlock()

	w.cancelFunc()
	w.state.IsRunning = false
}
