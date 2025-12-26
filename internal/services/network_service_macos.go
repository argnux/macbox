//go:build darwin

package services

import (
	"bufio"
	"bytes"
	"context"
	"macbox/pkg/network"
	"os/exec"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

type NetworkService struct {
}

func NewNetworkService() *NetworkService {
	return &NetworkService{}
}

func (ns *NetworkService) StartLiveLoop(ctx context.Context) {
	tickerCheckInterfaces := time.NewTicker(1 * time.Second)

	for {
		select {
		case <-ctx.Done():
			return
		case <-tickerCheckInterfaces.C:
			interfaces := ns.checkInterfaces()
			runtime.EventsEmit(ctx, "network-update", interfaces)
		}
	}
}

func (ns *NetworkService) CreateInterface(hardwarePortName string, newServiceName string) string {
	cmd := exec.Command("networksetup", "-createnetworkservice", newServiceName, hardwarePortName)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return parseNetworkError(out, err)
	}
	return ""
}

func (ns *NetworkService) DeleteInterface(serviceName string) string {
	cmd := exec.Command("networksetup", "-removenetworkservice", serviceName)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return parseNetworkError(out, err)
	}
	return ""
}

func (ns *NetworkService) UpdateInterface(data network.UpdatePayload) string {
	var err error

	currentName := data.OldName
	if data.NewName != "" && data.NewName != data.OldName {
		cmd := exec.Command("networksetup", "-renamenetworkservice", data.OldName, data.NewName)
		if out, e := cmd.CombinedOutput(); e != nil {
			return parseNetworkError(out, err)
		}
		currentName = data.NewName
	}

	if data.Method == "DHCP" {
		cmd := exec.Command("networksetup", "-setdhcp", currentName)
		err = cmd.Run()
	} else {
		cmd := exec.Command("networksetup", "-setmanual", currentName, data.IP, data.Mask, data.Gateway)
		if out, e := cmd.CombinedOutput(); e != nil {
			return parseNetworkError(out, err)
		}
	}

	if err != nil {
		return err.Error()
	}
	return ""
}

func (ns *NetworkService) checkInterfaces() []network.HardwareInterface {
	macMap := getMacAddressesMap()

	outputBytes, err := exec.Command("networksetup", "-listnetworkserviceorder").Output()
	if err != nil {
		return []network.HardwareInterface{}
	}
	output := string(outputBytes)

	hwMap := make(map[string]*network.HardwareInterface)

	var currentServiceName string

	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		if strings.HasPrefix(line, "(") && strings.Contains(line, ") ") {
			parts := strings.SplitN(line, ") ", 2)
			if len(parts) == 2 {
				currentServiceName = parts[1]
			}
			continue
		}

		if strings.HasPrefix(line, "(Hardware Port:") && currentServiceName != "" {
			re := regexp.MustCompile(`Hardware Port:\s+(.+?),\s+Device:\s+([^)]+)`)
			matches := re.FindStringSubmatch(line)

			if len(matches) == 3 {
				hwPortName := matches[1]
				deviceID := matches[2]

				logicIface := getServiceNetworkInfo(currentServiceName, deviceID)

				if _, exists := hwMap[deviceID]; !exists {
					hwMap[deviceID] = &network.HardwareInterface{
						Name:            hwPortName,
						Device:          deviceID,
						Mac:             macMap[deviceID],
						IsActive:        isInterfaceActive(deviceID),
						LogicInterfaces: []network.LogicInterface{},
					}
				}

				hwMap[deviceID].LogicInterfaces = append(hwMap[deviceID].LogicInterfaces, logicIface)
			}

			currentServiceName = ""
		}
	}

	result := make([]network.HardwareInterface, 0, len(hwMap))
	for _, hw := range hwMap {
		result = append(result, *hw)
	}

	sort.Slice(result, func(i, j int) bool {
		if result[i].Name == "Wi-Fi" && result[j].Name != "Wi-Fi" {
			return true
		}

		if result[i].Name != "Wi-Fi" && result[j].Name == "Wi-Fi" {
			return false
		}

		return result[i].Device < result[j].Device
	})

	return result
}

func getMacAddressesMap() map[string]string {
	result := make(map[string]string)
	out, err := exec.Command("networksetup", "-listallhardwareports").Output()
	if err != nil {
		return result
	}

	// Hardware Port: Wi-Fi
	// Device: en0
	// Ethernet Address: a4:83:e7:bd:cc:12

	scanner := bufio.NewScanner(bytes.NewReader(out))
	var currentDevice string

	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "Device: ") {
			currentDevice = strings.TrimPrefix(line, "Device: ")
		} else if strings.HasPrefix(line, "Ethernet Address: ") {
			mac := strings.TrimPrefix(line, "Ethernet Address: ")
			if currentDevice != "" {
				result[currentDevice] = mac
				currentDevice = ""
			}
		}
	}
	return result
}

func getServiceNetworkInfo(serviceName, deviceID string) network.LogicInterface {
	info := network.LogicInterface{
		ID:     serviceName,
		Name:   serviceName,
		Device: deviceID,
		Method: "Unknown",
	}

	out, err := exec.Command("networksetup", "-getinfo", serviceName).Output()
	if err != nil {
		return info
	}

	output := string(out)

	if strings.Contains(output, "Manual Configuration") {
		info.Method = "Manual"
	} else if strings.Contains(output, "DHCP Configuration") {
		info.Method = "DHCP"
	} else {
		info.Method = "Auto/Other"
	}

	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "IP address: ") {
			info.IP = strings.TrimPrefix(line, "IP address: ")
		} else if strings.HasPrefix(line, "Subnet mask: ") {
			info.Mask = strings.TrimPrefix(line, "Subnet mask: ")
		} else if strings.HasPrefix(line, "Router: ") {
			val := strings.TrimPrefix(line, "Router: ")
			if val == "(null)" {
				val = ""
			}
			info.Gateway = val
		}
	}

	return info
}

func isInterfaceActive(device string) bool {
	cmd := exec.Command("ifconfig", device)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(string(output), "status: active")
}

func parseNetworkError(output []byte, err error) string {
	if err == nil {
		return ""
	}

	rawOutput := strings.TrimSpace(string(output))

	if rawOutput == "" {
		return "Unknown system error (Exit status 1)"
	}

	if len(rawOutput) > 300 || strings.Contains(rawOutput, "networksetup -printcommands") {
		return "Internal Error: Invalid command parameters sent to system."
	}

	if strings.Contains(rawOutput, "not found") || strings.Contains(rawOutput, "does not exist") {
		return "Service or Device not found. It might have been deleted."
	}

	if strings.Contains(strings.ToLower(rawOutput), "privilege") || strings.Contains(strings.ToLower(rawOutput), "root") {
		return "Permission Denied: Please run the application with sudo."
	}

	if strings.Contains(rawOutput, "formatted") || strings.Contains(rawOutput, "valid IP") {
		return "System rejected this IP address format."
	}

	return "System Error: " + rawOutput
}
