package watcher

import "time"

type ProtocolParser interface {
	ID() string
	Name() string
	Description() string
	Parse(data []byte) (map[string]any, error)
}

type ParserMeta struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type WatcherConfig struct {
	Protocol string `json:"protocol"` // udp/tcp
	Port     int    `json:"port"`
	Parser   string `json:"parser"`
}

type WatcherState struct {
	Config    WatcherConfig `json:"config"`
	IsRunning bool          `json:"running"`
}

type UDPPacket struct {
	ID         int64          `json:"id"`        // v-for :key
	Timestamp  time.Time      `json:"timestamp"` // 12:00:01.555
	Protocol   string         `json:"protocol"`
	Parser     string         `json:"parser"`
	Size       int            `json:"size"`
	Payload    []byte         `json:"payload"`
	ParsedData map[string]any `json:"parsed_data"`
	FromIP     string         `json:"from_ip"`
	Port       int            `json:"port"`
}
