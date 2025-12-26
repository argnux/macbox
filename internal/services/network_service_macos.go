//go:build darwin

package services

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
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
	// ВАЖНО: hardwarePortName - это не "en0", а имя железки, например "USB 10/100 LAN"
	// Мы берем его из HardwareInterface.Name

	cmd := exec.Command("networksetup", "-createnetworkservice", newServiceName, hardwarePortName)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Sprintf("Error: %s", string(out))
	}
	return "" // Пустая строка = Успех
}

func (ns *NetworkService) DeleteInterface(serviceName string) string {
	// Нельзя удалять базовые "железные" сервисы, но networksetup обычно и не даст это сделать
	// либо пересоздаст их сам. Но с виртуальными работает отлично.

	cmd := exec.Command("networksetup", "-removenetworkservice", serviceName)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Sprintf("Error: %s", string(out))
	}
	return ""
}

func (ns *NetworkService) UpdateInterface(data network.UpdatePayload) string {
	var err error

	// 1. Если имя изменилось, сначала переименовываем
	currentName := data.OldName
	if data.NewName != "" && data.NewName != data.OldName {
		cmd := exec.Command("networksetup", "-renamenetworkservice", data.OldName, data.NewName)
		if out, e := cmd.CombinedOutput(); e != nil {
			return fmt.Sprintf("Rename failed: %s", string(out))
		}
		currentName = data.NewName
	}

	// 2. Применяем настройки IP
	if data.Method == "DHCP" {
		cmd := exec.Command("networksetup", "-setdhcp", currentName)
		err = cmd.Run()
	} else {
		// Статика
		// Если Gateway пустой, networksetup требует не передавать его вовсе или передать ""?
		// Обычно networksetup требует 3 аргумента. Если шлюза нет, можно попробовать передать пустую строку,
		// но иногда надежнее подавать " " (пробел) или не указывать.
		// Для простоты предположим, что поля валидны.
		cmd := exec.Command("networksetup", "-setmanual", currentName, data.IP, data.Mask, data.Gateway)
		if out, e := cmd.CombinedOutput(); e != nil {
			return fmt.Sprintf("IP Config failed: %s", string(out))
		}
	}

	if err != nil {
		return err.Error()
	}
	return ""
}

func (ns *NetworkService) checkInterfaces() []network.HardwareInterface {
	// 1. Получаем мак-адреса (DeviceID -> MAC)
	macMap := getMacAddressesMap()

	// 2. Получаем список сервисов
	outputBytes, err := exec.Command("networksetup", "-listnetworkserviceorder").Output()
	if err != nil {
		return []network.HardwareInterface{}
	}
	output := string(outputBytes)

	// 3. Используем Map для группировки по DeviceID (en0, en1...)
	// Key: "en0", Value: Указатель на структуру HardwareInterface
	hwMap := make(map[string]*network.HardwareInterface)

	// Временные переменные для парсинга
	var currentServiceName string

	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Шаг А: Ищем строку вида "(1) Wi-Fi" или "(2) My Custom IP"
		// Регулярка: начинает со скобки с цифрой, пробел, потом имя
		if strings.HasPrefix(line, "(") && strings.Contains(line, ") ") {
			parts := strings.SplitN(line, ") ", 2)
			if len(parts) == 2 {
				currentServiceName = parts[1] // Запоминаем "My Custom IP"
			}
			continue
		}

		// Шаг Б: Ищем строку "(Hardware Port: Wi-Fi, Device: en0)"
		// Она всегда идет СЛЕДОМ за именем сервиса
		if strings.HasPrefix(line, "(Hardware Port:") && currentServiceName != "" {
			// Парсим эту строку, чтобы достать en0 и Тип порта
			re := regexp.MustCompile(`Hardware Port:\s+(.+?),\s+Device:\s+([^)]+)`)
			matches := re.FindStringSubmatch(line)

			if len(matches) == 3 {
				hwPortName := matches[1] // "Wi-Fi" (Тип железа)
				deviceID := matches[2]   // "en0"

				// 1. Получаем детальную инфу по этому ЛОГИЧЕСКОМУ сервису
				logicIface := getServiceNetworkInfo(currentServiceName, deviceID)

				// 2. Проверяем, есть ли у нас уже этот ХАРДВАРНЫЙ порт в мапе
				if _, exists := hwMap[deviceID]; !exists {
					// Если нет - создаем
					hwMap[deviceID] = &network.HardwareInterface{
						Name:            hwPortName, // Называем группу по типу железа
						Device:          deviceID,
						Mac:             macMap[deviceID],
						IsActive:        isInterfaceActive(deviceID), // Проверяем линк 1 раз на порт
						LogicInterfaces: []network.LogicInterface{},
					}
				}

				// 3. Добавляем логический интерфейс в список этого хардварного порта
				hwMap[deviceID].LogicInterfaces = append(hwMap[deviceID].LogicInterfaces, logicIface)
			}

			// Сбрасываем имя, чтобы не дублировать
			currentServiceName = ""
		}
	}

	// 4. Превращаем Map обратно в Slice для отправки на фронт
	result := make([]network.HardwareInterface, 0, len(hwMap))
	for _, hw := range hwMap {
		result = append(result, *hw)
	}

	sort.Slice(result, func(i, j int) bool {
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
	// ID равен Имени, так как в networksetup имя уникально
	info := network.LogicInterface{
		ID:     serviceName,
		Name:   serviceName,
		Device: deviceID,
		Method: "Unknown",
	}

	// Вызываем getinfo для КОНКРЕТНОГО сервиса
	out, err := exec.Command("networksetup", "-getinfo", serviceName).Output()
	if err != nil {
		return info
	}

	output := string(out)

	// Определяем метод
	if strings.Contains(output, "Manual Configuration") {
		info.Method = "Manual"
	} else if strings.Contains(output, "DHCP Configuration") {
		info.Method = "DHCP"
	} else {
		info.Method = "Auto/Other"
	}

	// Парсим IP/Маску/Гейтвей
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
