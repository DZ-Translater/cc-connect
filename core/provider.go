package core

import "strings"

// GetProviderModels returns the configured model options for the active provider.
func GetProviderModels(providers []ProviderConfig, activeIdx int) []ModelOption {
	if activeIdx < 0 || activeIdx >= len(providers) {
		return nil
	}
	return providers[activeIdx].Models
}

// GetProviderModel returns the configured model for the active provider.
// If the active provider has no explicit model, fallback is returned.
func GetProviderModel(providers []ProviderConfig, activeIdx int, fallback string) string {
	if activeIdx < 0 || activeIdx >= len(providers) {
		return fallback
	}
	if model := providers[activeIdx].Model; model != "" {
		return model
	}
	return fallback
}

// SetProviderModel returns a copy of providers with the named provider's model updated.
// The second return value indicates whether a provider matched the given name.
func SetProviderModel(providers []ProviderConfig, name, model string) ([]ProviderConfig, bool) {
	updated := make([]ProviderConfig, len(providers))
	copy(updated, providers)
	for i := range updated {
		if updated[i].Name == name {
			updated[i].Model = model
			return updated, true
		}
	}
	return updated, false
}

// IsModelAllowed reports whether model is present in a configured model list.
// An empty list means that the provider has not opted into a static allowlist;
// callers may then use the agent's normal discovery/fallback behavior.
// Aliases are accepted case-insensitively, while model identifiers themselves
// are matched exactly because provider model IDs can be case-sensitive.
func IsModelAllowed(models []ModelOption, model string) bool {
	target := strings.TrimSpace(model)
	if target == "" || len(models) == 0 {
		return true
	}
	for _, option := range models {
		if strings.TrimSpace(option.Name) == target {
			return true
		}
		if alias := strings.TrimSpace(option.Alias); alias != "" && strings.EqualFold(alias, target) {
			return true
		}
	}
	return false
}
