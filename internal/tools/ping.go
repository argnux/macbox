package tools

import (
	"context"
	"fmt"
	"runtime"
	"sync"
	"time"

	probing "github.com/prometheus-community/pro-bing"
)

type PingTool struct {
	mu     sync.Mutex
	pinger *probing.Pinger
}

func NewPingTool() *PingTool {
	return &PingTool{}
}

func (pt *PingTool) Start(ctx context.Context, ip string, count int, logCallback func(string)) error {
	pinger, err := probing.NewPinger(ip)
	if err != nil {
		return err
	}

	if count > 0 {
		pinger.Count = count
		pinger.Timeout = time.Duration(count)*time.Second + time.Second*2
	}

	if runtime.GOOS == "windows" {
		pinger.SetPrivileged(true)
	}

	pinger.OnRecv = func(pkt *probing.Packet) {
		logCallback(fmt.Sprintf("%d bytes from %s: icmp_seq=%d time=%v\n",
			pkt.Nbytes, pkt.IPAddr, pkt.Seq, pkt.Rtt))
	}
	pinger.OnFinish = func(stats *probing.Statistics) {
		logCallback(fmt.Sprintf("\n--- %s ping statistics ---\n", stats.Addr))
		logCallback(fmt.Sprintf("%d packets transmitted, %d packets received, %v%% packet loss\n",
			stats.PacketsSent, stats.PacketsRecv, stats.PacketLoss))
		logCallback(fmt.Sprintf("round-trip min/avg/max/stddev = %v/%v/%v/%v\n",
			stats.MinRtt, stats.AvgRtt, stats.MaxRtt, stats.StdDevRtt))
	}

	pt.mu.Lock()
	pt.pinger = pinger
	pt.mu.Unlock()

	return pt.pinger.RunWithContext(ctx)
}

func (pt *PingTool) Stop() {
	if pt.isAvailable() {
		pt.pinger.Stop()
		pt.pinger = nil
	}
}

func (pt *PingTool) isAvailable() bool {
	pt.mu.Lock()
	defer pt.mu.Unlock()
	return pt.pinger != nil
}
