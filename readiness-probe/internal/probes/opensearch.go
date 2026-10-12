package probes

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"tracing-readiness-probe/internal/config"
)

// defaultRateLimitDelay is the pause after OpenSearch responds with 429 Too Many Requests.
const defaultRateLimitDelay = 60 * time.Second

// OpenSearchProbe checks OpenSearch by sending a GET request with basic authentication to its URL.
type OpenSearchProbe struct {
	client         *http.Client
	url            string
	creds          Credentials
	maxErrors      int
	maxRetries     int
	retryDelay     time.Duration
	rateLimitDelay time.Duration
}

// NewOpenSearchProbe returns a probe for the OpenSearch URL from cfg.
func NewOpenSearchProbe(cfg *config.Config, creds Credentials) (*OpenSearchProbe, error) {
	client := &http.Client{Timeout: cfg.Timeout}
	if cfg.TLS.Enabled {
		tlsConfig, err := newTLSConfig(cfg.TLS)
		if err != nil {
			return nil, err
		}
		client.Transport = &http.Transport{
			IdleConnTimeout: cfg.Timeout,
			TLSClientConfig: tlsConfig,
		}
	}
	return &OpenSearchProbe{
		client:         client,
		url:            cfg.Endpoint(),
		creds:          creds,
		maxErrors:      cfg.MaxErrors,
		maxRetries:     cfg.MaxRetries,
		retryDelay:     cfg.RetryDelay,
		rateLimitDelay: defaultRateLimitDelay,
	}, nil
}

func newTLSConfig(cfg config.TLS) (*tls.Config, error) {
	if cfg.InsecureSkipVerify {
		// The operator turns verification off explicitly with -insecureSkipVerify.
		return &tls.Config{InsecureSkipVerify: true}, nil // NOSONAR
	}

	cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load the client certificate and key: %w", err)
	}

	// Trust the system CAs in addition to the configured one.
	certPool, err := x509.SystemCertPool()
	if err != nil {
		return nil, fmt.Errorf("failed to load the system certificate pool: %w", err)
	}
	caCert, err := os.ReadFile(cfg.CAFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read the CA certificate: %w", err)
	}
	if !certPool.AppendCertsFromPEM(caCert) {
		return nil, fmt.Errorf("no valid certificate in the CA file %q", cfg.CAFile)
	}

	return &tls.Config{
		RootCAs:      certPool,
		Certificates: []tls.Certificate{cert},
	}, nil
}

// Check implements the Probe interface.
// Request errors count against maxErrors and non-200 responses count against maxRetries.
func (p *OpenSearchProbe) Check(ctx context.Context) bool {
	failedRequests, failedResponses := 0, 0
	for {
		delay := p.retryDelay
		status, err := p.get(ctx)
		switch {
		case err != nil:
			failedRequests++
			slog.Error("Failed to send a request to OpenSearch", "error", err, "remainingAttempts", p.maxErrors-failedRequests)
			if failedRequests >= p.maxErrors {
				return false
			}
		case status == http.StatusOK:
			return true
		default:
			failedResponses++
			slog.Error("Unexpected status code from OpenSearch", "status", status, "remainingAttempts", p.maxRetries-failedResponses)
			if failedResponses >= p.maxRetries {
				return false
			}
			if status == http.StatusTooManyRequests {
				delay = p.rateLimitDelay
			}
		}
		if !wait(ctx, delay) {
			return false
		}
	}
}

func (p *OpenSearchProbe) get(ctx context.Context) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, p.url, http.NoBody)
	if err != nil {
		return 0, err
	}
	req.SetBasicAuth(p.creds.Username, p.creds.Password)

	resp, err := p.client.Do(req)
	if err != nil {
		return 0, err
	}
	if err := resp.Body.Close(); err != nil && !errors.Is(err, context.Canceled) {
		slog.Warn("Failed to close the OpenSearch response body", "error", err)
	}
	return resp.StatusCode, nil
}

// Name implements the Probe interface.
func (p *OpenSearchProbe) Name() string {
	return config.StorageOpenSearch
}
