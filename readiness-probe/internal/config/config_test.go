package config

import (
	"errors"
	"flag"
	"io"
	"strings"
	"testing"
	"time"
)

func TestParseAppliesDefaults(t *testing.T) {
	cfg, err := Parse([]string{"-host=cassandra.svc", "-authSecretName=jaeger-cassandra"}, io.Discard)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := Config{
		ServicePort:     8080,
		ShutdownTimeout: 5 * time.Second,
		Storage:         StorageCassandra,
		Host:            "cassandra.svc",
		MaxErrors:       3,
		MaxRetries:      3,
		Timeout:         5 * time.Second,
		RetryDelay:      5 * time.Second,
		Namespace:       "tracing",
		AuthSecretName:  "jaeger-cassandra",
		Keyspace:        "jaeger",
		Datacenter:      "datacenter1",
		TestTable:       "service_names",
	}
	if *cfg != want {
		t.Errorf("expected %+v, got %+v", want, *cfg)
	}
}

// The chart passes these arguments, so their names and formats must stay stable.
func TestParseAcceptsChartArguments(t *testing.T) {
	cfg, err := Parse([]string{
		"-namespace=jaeger",
		"-storage=cassandra",
		"-authSecretName=jaeger-cassandra",
		"-datacenter=dc2",
		"-keyspace=traces",
		"-testtable=operation_names",
		"-host=cassandra.cassandra.svc",
		"-port=9042",
		"-tlsEnabled=true",
		"-caPath=/cassandra-tls/ca-cert.pem",
		"-crtPath=/cassandra-tls/client-cert.pem",
		"-keyPath=/cassandra-tls/client-key.pem",
		"-errors=5",
		"-retries=4",
		"-timeout=7",
		"-retryDelay=2",
		"-shutdownTimeout=9",
		"-servicePort=8081",
	}, io.Discard)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := Config{
		ServicePort:     8081,
		ShutdownTimeout: 9 * time.Second,
		Storage:         StorageCassandra,
		Host:            "cassandra.cassandra.svc",
		Port:            9042,
		MaxErrors:       5,
		MaxRetries:      4,
		Timeout:         7 * time.Second,
		RetryDelay:      2 * time.Second,
		TLS: TLS{
			Enabled:  true,
			CAFile:   "/cassandra-tls/ca-cert.pem",
			CertFile: "/cassandra-tls/client-cert.pem",
			KeyFile:  "/cassandra-tls/client-key.pem",
		},
		Namespace:      "jaeger",
		AuthSecretName: "jaeger-cassandra",
		Keyspace:       "traces",
		Datacenter:     "dc2",
		TestTable:      "operation_names",
	}
	if *cfg != want {
		t.Errorf("expected %+v, got %+v", want, *cfg)
	}
}

func TestParseNormalizesStorageCase(t *testing.T) {
	cfg, err := Parse([]string{"-storage=OpenSearch", "-host=https://opensearch:9200", "-authSecretName=s"}, io.Discard)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Storage != StorageOpenSearch {
		t.Errorf("expected storage %q, got %q", StorageOpenSearch, cfg.Storage)
	}
}

func TestParseAllowsInsecureTLSWithoutCertificateFiles(t *testing.T) {
	cfg, err := Parse([]string{"-host=h", "-authSecretName=s", "-tlsEnabled=true", "-insecureSkipVerify=true"}, io.Discard)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !cfg.TLS.Enabled || !cfg.TLS.InsecureSkipVerify {
		t.Errorf("expected TLS enabled without verification, got %+v", cfg.TLS)
	}
}

func TestParseRejectsInvalidArguments(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr string
	}{
		{"missing host", []string{"-authSecretName=s"}, "-host"},
		{"missing secret name", []string{"-host=h"}, "-authSecretName"},
		{"unsupported storage", []string{"-host=h", "-authSecretName=s", "-storage=mongo"}, "-storage"},
		{"TLS without CA file", []string{"-host=h", "-authSecretName=s", "-tlsEnabled=true", "-crtPath=c", "-keyPath=k"}, "-caPath"},
		{"negative timeout", []string{"-host=h", "-authSecretName=s", "-timeout=-1"}, "-timeout"},
		{"unknown flag", []string{"-host=h", "-authSecretName=s", "-cassandra.host=h"}, "cassandra.host"},
		{"non-numeric timeout", []string{"-host=h", "-authSecretName=s", "-timeout=5s"}, "timeout"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := Parse(tt.args, io.Discard)
			if err == nil {
				t.Fatal("expected an error, got nil")
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Errorf("expected the error to mention %q, got %q", tt.wantErr, err)
			}
		})
	}
}

func TestParseReturnsErrHelp(t *testing.T) {
	_, err := Parse([]string{"-help"}, io.Discard)
	if !errors.Is(err, flag.ErrHelp) {
		t.Errorf("expected flag.ErrHelp, got %v", err)
	}
}

func TestEndpoint(t *testing.T) {
	tests := []struct {
		name string
		cfg  Config
		want string
	}{
		{"without port", Config{Host: "https://opensearch:9200"}, "https://opensearch:9200"},
		{"with port", Config{Host: "http://opensearch", Port: 9200}, "http://opensearch:9200"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.cfg.Endpoint(); got != tt.want {
				t.Errorf("expected %q, got %q", tt.want, got)
			}
		})
	}
}
