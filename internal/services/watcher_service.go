package services

import (
	"context"
	"fmt"
	"io"
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
	service.registerParser(&parsers.AsciiParser{})
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

func (w *WatcherService) startUDP(ctx context.Context, port int, dataChan chan<- watcher.UDPPacket, errChan chan<- error) {
	addr, err := net.ResolveUDPAddr("udp", fmt.Sprintf(":%d", port))
	if err != nil {
		errChan <- err
		return
	}
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		errChan <- err
		return
	}

	go func() {
		<-ctx.Done()
		conn.Close()
	}()

	buffer := make([]byte, 2048)
	for {
		n, from, err := conn.ReadFromUDP(buffer)
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				errChan <- err
				return
			}
		}

		toSend := make([]byte, n)
		copy(toSend, buffer[:n])

		packet := watcher.UDPPacket{
			Timestamp: time.Now(),
			Size:      n,
			Payload:   toSend,
			FromIP:    from.String(),
		}

		select {
		case dataChan <- packet:
		case <-ctx.Done():
			return
		}
	}
}

func (w *WatcherService) startTCP(ctx context.Context, port int, dataChan chan<- watcher.UDPPacket, errChan chan<- error) {
	addr := fmt.Sprintf(":%d", port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		errChan <- err
		return
	}

	go func() {
		<-ctx.Done()
		listener.Close()
	}()

	for {
		conn, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				errChan <- err
				return
			}
		}

		go w.handleTCPConnection(ctx, conn, dataChan)
	}
}

func (w *WatcherService) handleTCPConnection(ctx context.Context, conn net.Conn, dataChan chan<- watcher.UDPPacket) {
	defer conn.Close()
	remoteAddr := conn.RemoteAddr().String()
	buffer := make([]byte, 4096)

	for {
		n, err := conn.Read(buffer)
		if err != nil {
			if err != io.EOF {
				fmt.Printf("TCP read error from %s: %v\n", remoteAddr, err)
			}
			return
		}

		toSend := make([]byte, n)
		copy(toSend, buffer[:n])

		packet := watcher.UDPPacket{
			Timestamp: time.Now(),
			Size:      n,
			Payload:   toSend,
			FromIP:    remoteAddr,
		}

		select {
		case dataChan <- packet:
		case <-ctx.Done():
			return
		}
	}
}

func (w *WatcherService) Start() {
	ctx, cancel := context.WithCancel(w.ctx)

	w.mu.Lock()
	w.cancelFunc = cancel
	w.state.IsRunning = true
	if p, ok := w.parsersMap[w.state.Config.Parser]; ok {
		w.currentParser = p
	}
	currentParser := w.currentParser
	protocol := w.state.Config.Protocol
	port := w.state.Config.Port
	w.mu.Unlock()

	dataChan := make(chan watcher.UDPPacket, 100)
	errChan := make(chan error)

	if protocol == "tcp" {
		go w.startTCP(ctx, port, dataChan, errChan)
	} else {
		go w.startUDP(ctx, port, dataChan, errChan)
	}

	go func() {
		var id int64 = 0

		defer func() {
			w.mu.Lock()
			w.state.IsRunning = false
			w.mu.Unlock()
		}()

		for {
			select {
			case <-ctx.Done():
				return

			case packet := <-dataChan:
				packet.ID = id
				packet.Protocol = protocol
				packet.Parser = currentParser.ID()
				packet.Port = port

				// TODO: parse chunks instead of full packets
				parsedData, _ := currentParser.Parse(packet.Payload)
				packet.ParsedData = parsedData

				runtime.EventsEmit(w.ctx, "packet_received", packet)
				id++

			case err := <-errChan:
				fmt.Printf("Listener Error: %v\n", err)
				w.Stop()

				runtime.EventsEmit(w.ctx, "watcher_error", err.Error())
				return
			}
		}
	}()
}

func (w *WatcherService) Stop() {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.cancelFunc != nil {
		w.cancelFunc()
	}
	w.state.IsRunning = false
}
