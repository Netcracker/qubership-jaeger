package probes

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"tracing-readiness-probe/internal/config"
)

var testCredentials = Credentials{Username: "user", Password: "pass"}

// statusServer responds with the queued status codes one by one and with 200 after the queue is empty.
// It responds with 401 to requests without the test credentials.
func statusServer(t *testing.T, newServer func(http.Handler) *httptest.Server, statuses ...int) (*httptest.Server, *atomic.Int32) {
	t.Helper()
	var calls atomic.Int32
	srv := newServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		call := int(calls.Add(1))
		username, password, ok := r.BasicAuth()
		if !ok || username != testCredentials.Username || password != testCredentials.Password {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		if call <= len(statuses) {
			w.WriteHeader(statuses[call-1])
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	return srv, &calls
}

func openSearchTestConfig(url string) *config.Config {
	return &config.Config{
		Host:       url,
		MaxErrors:  3,
		MaxRetries: 3,
		Timeout:    5 * time.Second,
		RetryDelay: time.Millisecond,
	}
}

func newTestOpenSearchProbe(t *testing.T, cfg *config.Config, creds Credentials) *OpenSearchProbe {
	t.Helper()
	probe, err := NewOpenSearchProbe(cfg, creds)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	probe.rateLimitDelay = time.Millisecond
	return probe
}

func TestOpenSearchCheckSendsCredentials(t *testing.T) {
	srv, calls := statusServer(t, httptest.NewServer)
	probe := newTestOpenSearchProbe(t, openSearchTestConfig(srv.URL), testCredentials)

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result")
	}
	if calls.Load() != 1 {
		t.Errorf("expected 1 request, got %d", calls.Load())
	}
}

func TestOpenSearchCheckFailsWithWrongCredentials(t *testing.T) {
	srv, calls := statusServer(t, httptest.NewServer)
	probe := newTestOpenSearchProbe(t, openSearchTestConfig(srv.URL), Credentials{Username: "user", Password: "wrong"})

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result")
	}
	// Every one of the 3 allowed errors covers 3 non-200 responses.
	if calls.Load() != 9 {
		t.Errorf("expected 9 requests, got %d", calls.Load())
	}
}

func TestOpenSearchCheckRetriesAfterNon200Response(t *testing.T) {
	srv, calls := statusServer(t, httptest.NewServer, http.StatusServiceUnavailable, http.StatusTooManyRequests)
	probe := newTestOpenSearchProbe(t, openSearchTestConfig(srv.URL), testCredentials)

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result after retries")
	}
	if calls.Load() != 3 {
		t.Errorf("expected 3 requests, got %d", calls.Load())
	}
}

// The probe tolerates more non-200 responses than MaxRetries, as long as MaxErrors is not used up.
func TestOpenSearchCheckRecoversAfterMoreResponsesThanMaxRetries(t *testing.T) {
	srv, calls := statusServer(t, httptest.NewServer,
		http.StatusServiceUnavailable, http.StatusServiceUnavailable, http.StatusServiceUnavailable)
	probe := newTestOpenSearchProbe(t, openSearchTestConfig(srv.URL), testCredentials)

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result on the fourth response")
	}
	if calls.Load() != 4 {
		t.Errorf("expected 4 requests, got %d", calls.Load())
	}
}

func TestOpenSearchCheckFailsAfterMaxRetries(t *testing.T) {
	statuses := make([]int, 10)
	for i := range statuses {
		statuses[i] = http.StatusServiceUnavailable
	}
	srv, calls := statusServer(t, httptest.NewServer, statuses...)
	cfg := openSearchTestConfig(srv.URL)
	cfg.MaxErrors = 2
	probe := newTestOpenSearchProbe(t, cfg, testCredentials)

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result")
	}
	if calls.Load() != 6 {
		t.Errorf("expected 6 requests, got %d", calls.Load())
	}
}

func TestOpenSearchCheckFailsImmediatelyWithoutRetries(t *testing.T) {
	srv, calls := statusServer(t, httptest.NewServer, http.StatusServiceUnavailable)
	cfg := openSearchTestConfig(srv.URL)
	cfg.MaxRetries = 0
	probe := newTestOpenSearchProbe(t, cfg, testCredentials)

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result")
	}
	if calls.Load() != 1 {
		t.Errorf("expected 1 request, got %d", calls.Load())
	}
}

func TestOpenSearchCheckWaitsAfterRateLimit(t *testing.T) {
	srv, calls := statusServer(t, httptest.NewServer, http.StatusTooManyRequests)
	probe := newTestOpenSearchProbe(t, openSearchTestConfig(srv.URL), testCredentials)
	probe.rateLimitDelay = time.Hour

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	if probe.Check(ctx) {
		t.Fatal("expected an unhealthy result while the probe waits for the rate limit")
	}
	if calls.Load() != 1 {
		t.Errorf("expected 1 request, got %d", calls.Load())
	}
}

// The probe backs off after the last allowed 429 too, so that the next check does not start right away.
func TestOpenSearchCheckWaitsAfterLastRateLimit(t *testing.T) {
	srv, calls := statusServer(t, httptest.NewServer, http.StatusTooManyRequests)
	cfg := openSearchTestConfig(srv.URL)
	cfg.MaxErrors = 1
	cfg.MaxRetries = 1
	probe := newTestOpenSearchProbe(t, cfg, testCredentials)
	probe.rateLimitDelay = 50 * time.Millisecond

	start := time.Now()
	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result")
	}
	if elapsed := time.Since(start); elapsed < probe.rateLimitDelay {
		t.Errorf("expected the check to wait at least %s, it returned after %s", probe.rateLimitDelay, elapsed)
	}
	if calls.Load() != 1 {
		t.Errorf("expected 1 request, got %d", calls.Load())
	}
}

func TestOpenSearchCheckFailsWithInvalidURL(t *testing.T) {
	probe := newTestOpenSearchProbe(t, openSearchTestConfig("http://opensearch\x7f:9200"), testCredentials)

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result for an invalid URL")
	}
}

func TestOpenSearchProbeName(t *testing.T) {
	probe := newTestOpenSearchProbe(t, openSearchTestConfig("http://opensearch:9200"), testCredentials)

	if probe.Name() != config.StorageOpenSearch {
		t.Errorf("expected name %q, got %q", config.StorageOpenSearch, probe.Name())
	}
}

func TestOpenSearchCheckFailsAfterMaxErrors(t *testing.T) {
	srv, _ := statusServer(t, httptest.NewServer)
	url := srv.URL
	srv.Close()
	cfg := openSearchTestConfig(url)
	cfg.MaxErrors = 2
	probe := newTestOpenSearchProbe(t, cfg, testCredentials)

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result for a closed server")
	}
}

// failingTransport fails the first failures requests and forwards the rest.
type failingTransport struct {
	failures int
	calls    atomic.Int32
}

func (f *failingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if int(f.calls.Add(1)) <= f.failures {
		return nil, errors.New("connection refused")
	}
	return http.DefaultTransport.RoundTrip(req)
}

func TestOpenSearchCheckRecoversAfterMaxErrors(t *testing.T) {
	srv, _ := statusServer(t, httptest.NewServer)
	probe := newTestOpenSearchProbe(t, openSearchTestConfig(srv.URL), testCredentials)
	transport := &failingTransport{failures: 3}
	probe.client.Transport = transport

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result after three request errors")
	}
	if calls := transport.calls.Load(); calls != 4 {
		t.Errorf("expected 4 requests, got %d", calls)
	}
}

func TestOpenSearchCheckFailsAfterOneErrorMoreThanMaxErrors(t *testing.T) {
	srv, _ := statusServer(t, httptest.NewServer)
	probe := newTestOpenSearchProbe(t, openSearchTestConfig(srv.URL), testCredentials)
	transport := &failingTransport{failures: 4}
	probe.client.Transport = transport

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result after four request errors")
	}
	if calls := transport.calls.Load(); calls != 4 {
		t.Errorf("expected 4 requests, got %d", calls)
	}
}

func TestOpenSearchCheckOverVerifiedTLS(t *testing.T) {
	srv, _ := statusServer(t, httptest.NewTLSServer)
	certFile, keyFile := writeClientCertificate(t)
	cfg := openSearchTestConfig(srv.URL)
	cfg.TLS = config.TLS{Enabled: true, CAFile: writeServerCA(t, srv), CertFile: certFile, KeyFile: keyFile}
	probe := newTestOpenSearchProbe(t, cfg, testCredentials)

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result")
	}
}

func TestOpenSearchCheckRejectsUntrustedServerCertificate(t *testing.T) {
	srv, _ := statusServer(t, httptest.NewTLSServer)
	certFile, keyFile := writeClientCertificate(t)
	cfg := openSearchTestConfig(srv.URL)
	cfg.MaxErrors = 1
	// The client certificate is self-signed and did not sign the server certificate.
	cfg.TLS = config.TLS{Enabled: true, CAFile: certFile, CertFile: certFile, KeyFile: keyFile}
	probe := newTestOpenSearchProbe(t, cfg, testCredentials)

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result")
	}
}

func TestOpenSearchCheckOverInsecureTLS(t *testing.T) {
	srv, _ := statusServer(t, httptest.NewTLSServer)
	cfg := openSearchTestConfig(srv.URL)
	cfg.TLS = config.TLS{Enabled: true, InsecureSkipVerify: true}
	probe := newTestOpenSearchProbe(t, cfg, testCredentials)

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result")
	}
}

func TestNewOpenSearchProbeRejectsInvalidTLSFiles(t *testing.T) {
	certFile, keyFile := writeClientCertificate(t)
	notPEM := filepath.Join(t.TempDir(), "ca.pem")
	if err := os.WriteFile(notPEM, []byte("not a certificate"), 0o600); err != nil {
		t.Fatalf("failed to write the file: %v", err)
	}

	tests := []struct {
		name string
		tls  config.TLS
	}{
		{"missing client certificate", config.TLS{Enabled: true, CAFile: certFile, CertFile: "missing.pem", KeyFile: keyFile}},
		{"missing CA file", config.TLS{Enabled: true, CAFile: "missing.pem", CertFile: certFile, KeyFile: keyFile}},
		{"CA file without certificates", config.TLS{Enabled: true, CAFile: notPEM, CertFile: certFile, KeyFile: keyFile}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := openSearchTestConfig("https://opensearch:9200")
			cfg.TLS = tt.tls
			if _, err := NewOpenSearchProbe(cfg, testCredentials); err == nil {
				t.Fatal("expected an error, got nil")
			}
		})
	}
}

func writeServerCA(t *testing.T, srv *httptest.Server) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "ca-cert.pem")
	writePEM(t, path, "CERTIFICATE", srv.Certificate().Raw)
	return path
}

// writeClientCertificate writes a self-signed certificate and its key and returns their paths.
func writeClientCertificate(t *testing.T) (certFile, keyFile string) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("failed to generate the key: %v", err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{Organization: []string{"test"}},
		NotBefore:    time.Now().Add(-time.Minute),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("failed to create the certificate: %v", err)
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		t.Fatalf("failed to encode the key: %v", err)
	}

	dir := t.TempDir()
	certFile = filepath.Join(dir, "client-cert.pem")
	keyFile = filepath.Join(dir, "client-key.pem")
	writePEM(t, certFile, "CERTIFICATE", certDER)
	writePEM(t, keyFile, "EC PRIVATE KEY", keyDER)
	return certFile, keyFile
}

func writePEM(t *testing.T, path, blockType string, der []byte) {
	t.Helper()
	data := pem.EncodeToMemory(&pem.Block{Type: blockType, Bytes: der})
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatalf("failed to write %s: %v", path, err)
	}
}
