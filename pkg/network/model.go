package network

type HardwareInterface struct {
	Name            string           `json:"name"`
	Device          string           `json:"device"`
	Mac             string           `json:"mac"`
	IsActive        bool             `json:"isActive"` // For indicator (green/gray)
	LogicInterfaces []LogicInterface `json:"logicInterfaces"`
}

type LogicInterface struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Device  string `json:"device"`
	IP      string `json:"ip"`
	Mask    string `json:"mask"`
	Gateway string `json:"gateway"`
	Method  string `json:"method"` // "DHCP" or "Manual"
}

type UpdatePayload struct {
	OldName string `json:"oldName"`
	NewName string `json:"newName"`
	Method  string `json:"method"`
	IP      string `json:"ip"`
	Mask    string `json:"mask"`
	Gateway string `json:"gateway"`
}
