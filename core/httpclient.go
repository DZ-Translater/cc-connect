package core

import (
	"net/http"
	"strings"
	"time"
)

// HTTPClient is a shared HTTP client with a reasonable timeout for platform use.
var HTTPClient = &http.Client{
	Timeout: 30 * time.Second,
}

// ProviderModelsURL appends the standard models path without duplicating /v1
// when a provider base URL already includes the API version prefix.
func ProviderModelsURL(baseURL string) string {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if strings.HasSuffix(strings.ToLower(baseURL), "/v1") {
		return baseURL + "/models"
	}
	return baseURL + "/v1/models"
}
