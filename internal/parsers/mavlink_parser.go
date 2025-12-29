package parsers

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"reflect"
	"strings"

	"github.com/bluenviron/gomavlib/v3/pkg/dialect"
	"github.com/bluenviron/gomavlib/v3/pkg/dialects/common"
	"github.com/bluenviron/gomavlib/v3/pkg/frame"
	"github.com/bluenviron/gomavlib/v3/pkg/message"
)

type MavlinkParser struct{}

func (p *MavlinkParser) ID() string          { return "mavlink" }
func (p *MavlinkParser) Name() string        { return "Mavlink Parser" }
func (p *MavlinkParser) Description() string { return "Decode mavlink packet" }

func (p *MavlinkParser) Parse(data []byte) (map[string]any, error) {
	var frameReader frame.Reader
	frameReader.BufByteReader = bufio.NewReader(bytes.NewReader(data))
	frameReader.DialectRW = &dialect.ReadWriter{
		Dialect: common.Dialect,
	}
	err := frameReader.DialectRW.Initialize()
	if err != nil {
		return map[string]any{}, err
	}
	err = frameReader.Initialize()
	if err != nil {
		return map[string]any{}, err
	}

	fr, err := frameReader.Read()
	if err != nil {
		return nil, fmt.Errorf("decode error: %w", err)
	}

	msg := fr.GetMessage()
	if msg == nil {
		return nil, fmt.Errorf("no message in frame")
	}

	fullType := reflect.TypeOf(msg).Elem().Name()
	msgName := strings.TrimPrefix(fullType, "Message")
	msgName = strings.ToUpper(msgName)

	formatted := p.formatSpecificMessage(msg)

	jsonBytes, err := json.Marshal(msg)
	if err != nil {
		return nil, err
	}
	var rawPayload map[string]any
	if err := json.Unmarshal(jsonBytes, &rawPayload); err != nil {
		return nil, err
	}

	result := map[string]any{
		"system_id":    fr.GetSystemID(),
		"component_id": fr.GetComponentID(),
		"message_id":   msg.GetID(),
		"name":         msgName,
		"summary":      formatted,
		"payload":      rawPayload,
	}
	return result, nil
}

func (p *MavlinkParser) formatSpecificMessage(msg message.Message) map[string]any {
	res := make(map[string]any)

	switch m := msg.(type) {
	case *common.MessageHeartbeat:
		isArmed := (m.BaseMode & common.MAV_MODE_FLAG_SAFETY_ARMED) != 0
		status := "DISARMED"
		if isArmed {
			status = "ARMED"
		}
		res["State"] = status
		res["Mav Type"] = fmt.Sprintf("%d", m.Type)
		res["Mode"] = fmt.Sprintf("Base: %d / Custom: %d", m.BaseMode, m.CustomMode)

	case *common.MessageAttitude:
		res["Roll"] = toDeg(m.Roll)
		res["Pitch"] = toDeg(m.Pitch)
		res["Yaw"] = toDeg(m.Yaw)

	case *common.MessageGlobalPositionInt:
		res["Lat"] = float64(m.Lat) / 1e7
		res["Lon"] = float64(m.Lon) / 1e7
		res["Alt"] = fmt.Sprintf("%.2f m", float64(m.RelativeAlt)/1000.0)
		res["Heading"] = float64(m.Hdg) / 100.0

	case *common.MessageSysStatus:
		res["Battery"] = fmt.Sprintf("%.2f V", float64(m.VoltageBattery)/1000.0)
		res["Current"] = fmt.Sprintf("%.2f A", float64(m.CurrentBattery)/100.0)
		res["CPU Load"] = fmt.Sprintf("%d %%", m.Load/10)
	}

	if len(res) == 0 {
		return nil
	}
	return res
}

func toDeg(rad float32) string {
	val := float64(rad) * (180.0 / math.Pi)
	return fmt.Sprintf("%.1f°", val)
}
