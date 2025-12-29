package parsers

type RawParser struct{}

func (p *RawParser) ID() string          { return "raw" }
func (p *RawParser) Name() string        { return "Raw Hex" }
func (p *RawParser) Description() string { return "Displays raw bytes without decoding" }

func (p *RawParser) Parse(data []byte) (map[string]any, error) {
	return map[string]any{"message": "Raw bytes mode. See Hex Dump below."}, nil
}
