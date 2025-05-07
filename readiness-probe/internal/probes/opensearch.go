package probes

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"
)

const (
	// rateLimitTimeout is the duration to wait when receiving a 429 Too Many Requests response
	rateLimitTimeout = 5 * time.Second
)

// OpenSearchProbe implements the Probe interface for OpenSearch
type OpenSearchProbe struct {
	client     *http.Client
	url        string
	index      string
	maxRetries int
	retryDelay time.Duration
}

// OpenSearchConfig extends BaseProbeConfig with OpenSearch-specific settings
type OpenSearchConfig struct {
	*BaseProbeConfig
	Host     string
	Port     int
	Index    string
	Username string
	Password string
}

// GetBaseConfig implements the ProbeConfig interface
func (c *OpenSearchConfig) GetBaseConfig() *BaseProbeConfig {
	return c.BaseProbeConfig
}

// NewOpenSearchProbeFromConfig creates a new OpenSearch probe from configuration
func NewOpenSearchProbeFromConfig(cfg *OpenSearchConfig) (*OpenSearchProbe, error) {
	client := &http.Client{
		Timeout: cfg.Timeout,
	}

	if cfg.TLSEnabled {
		tlsConfig := &tls.Config{
			Certificates: []tls.Certificate{},
			RootCAs:      x509.NewCertPool(),
		}

		// Load client certificate
		cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
		if err != nil {
			return nil, fmt.Errorf("failed to load client certificate: %w", err)
		}
		tlsConfig.Certificates = append(tlsConfig.Certificates, cert)

		// Load CA certificate
		caCert, err := os.ReadFile(cfg.CAFile)
		if err != nil {
			return nil, fmt.Errorf("failed to read CA certificate: %w", err)
		}
		if !tlsConfig.RootCAs.AppendCertsFromPEM(caCert) {
			return nil, fmt.Errorf("failed to append CA certificate")
		}

		client.Transport = &http.Transport{
			TLSClientConfig: tlsConfig,
		}
	}

	url := fmt.Sprintf("https://%s:%d/%s/_search", cfg.Host, cfg.Port, cfg.Index)
	if !cfg.TLSEnabled {
		url = fmt.Sprintf("http://%s:%d/%s/_search", cfg.Host, cfg.Port, cfg.Index)
	}

	return NewOpenSearchProbe(client, url, cfg.Index, cfg.MaxRetries, cfg.Timeout), nil
}

// NewOpenSearchProbe creates a new OpenSearch probe
func NewOpenSearchProbe(client *http.Client, url, index string, maxRetries int, retryDelay time.Duration) *OpenSearchProbe {
	return &OpenSearchProbe{
		client:     client,
		url:        url,
		index:      index,
		maxRetries: maxRetries,
		retryDelay: retryDelay,
	}
}

// Check implements the Probe interface
func (p *OpenSearchProbe) Check(ctx context.Context) bool {
	for i := range make([]struct{}, p.maxRetries) {
		select {
		case <-ctx.Done():
			return false
		default:
			req, err := http.NewRequestWithContext(ctx, "GET", p.url, nil)
			if err != nil {
				slog.Error("Failed to create request", "error", err)
				continue
			}

			resp, err := p.client.Do(req)
			if err != nil {
				slog.Error("Failed to execute OpenSearch query", "error", err)
			} else {
				resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					return true
				}
				if resp.StatusCode == http.StatusTooManyRequests {
					slog.Warn("Rate limited by OpenSearch, waiting before retry")
					time.Sleep(rateLimitTimeout)
					continue
				}
				slog.Error("Unexpected status code from OpenSearch", "status", resp.StatusCode)
			}

			if i < p.maxRetries-1 {
				slog.Info("Retrying OpenSearch health check", "attempt", i+1, "remaining", p.maxRetries-i-1)
				time.Sleep(p.retryDelay)
			}
		}
	}
	return false
}

// Name implements the Probe interface
func (p *OpenSearchProbe) Name() string {
	return "opensearch"
}
