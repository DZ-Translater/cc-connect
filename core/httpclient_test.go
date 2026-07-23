package core

import "testing"

func TestProviderModelsURLAvoidsDuplicateV1(t *testing.T) {
	tests := map[string]string{
		"https://api.example.com":          "https://api.example.com/v1/models",
		"https://api.example.com/":         "https://api.example.com/v1/models",
		"https://api.example.com/v1":       "https://api.example.com/v1/models",
		"https://api.example.com/v1/":      "https://api.example.com/v1/models",
		"https://api.example.com/proxy/v1": "https://api.example.com/proxy/v1/models",
	}
	for input, want := range tests {
		if got := ProviderModelsURL(input); got != want {
			t.Errorf("ProviderModelsURL(%q) = %q, want %q", input, got, want)
		}
	}
}
