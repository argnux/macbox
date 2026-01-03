package parsers

import "strings"

type AsciiParser struct{}

func (p *AsciiParser) ID() string   { return "ascii" }
func (p *AsciiParser) Name() string { return "ASCII" }
func (p *AsciiParser) Description() string {
	return "Displays printable ASCII characters, replaces others with '.'"
}

func (p *AsciiParser) Parse(data []byte) (map[string]any, error) {
	if len(data) == 0 {
		return map[string]any{
			"message": "<Empty Payload>",
		}, nil
	}

	var sb strings.Builder
	sb.Grow(len(data))

	printableCount := 0

	for _, b := range data {
		if b >= 32 && b <= 126 {
			sb.WriteByte(b)
			printableCount++
		} else {
			sb.WriteByte('.')
		}
	}

	cleanedText := sb.String()

	isText := false
	if len(data) > 0 {
		isText = (float64(printableCount) / float64(len(data))) > 0.9
	}

	return map[string]any{
		"message": cleanedText,

		"stats": map[string]any{
			"total_bytes":     len(data),
			"printable_bytes": printableCount,
			"heuristic_guess": map[bool]string{true: "Likely Text", false: "Binary Data"}[isText],
		},
	}, nil
}
