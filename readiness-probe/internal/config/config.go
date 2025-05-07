package config

import (
	"crypto/tls"
	"crypto/x509"
	"flag"
	"log/slog"
	"os"
	"time"
)

// Config holds all configuration for the application
type Config struct {
	// Common configuration
	ServicePort     int
	ShutdownTimeout time.Duration
	
	MaxErrors       int
	MaxRetries      int
	Timeout         time.Duration
	
	TLSEnabled      bool
	CAFile          string
	CertFile        string
	KeyFile         string
	
	StorageType     string

	// Cassandra specific configuration
	CassandraHost       string
	CassandraPort       int
	CassandraKeyspace   string
	CassandraDatacenter string
	CassandraTestTable  string
	CassandraUsername   string
	CassandraPassword   string

	// OpenSearch specific configuration
	OpenSearchHost       string
	OpenSearchPort       int
	OpenSearchIndex string
	OpenSearchUsername string
	OpenSearchPassword string
}

// LoadConfig loads and validates the configuration
func LoadConfig() *Config {
	cfg := &Config{}

	// Common configuration
	flag.IntVar(&cfg.ServicePort, "service-port", 8080, "The port for running service")
	flag.DurationVar(&cfg.ShutdownTimeout, "shutdown-timeout", 5*time.Second, "The number of seconds for graceful shutdown")
	
	flag.IntVar(&cfg.MaxErrors, "max-errors", 3, "The number of allowed errors for checking probe")
	flag.IntVar(&cfg.MaxRetries, "max-retries", 3, "The number of retries for checking probe")
	flag.DurationVar(&cfg.Timeout, "timeout", 5*time.Second, "The number of seconds for failing probe by timeout")
	
	flag.BoolVar(&cfg.TLSEnabled, "tls.enabled", false, "Enable TLS for connection to the storage")
	flag.StringVar(&cfg.CAFile, "tls.ca", "", "Path to CA certificate file")
	flag.StringVar(&cfg.CertFile, "tls.cert", "", "Path to client certificate file")
	flag.StringVar(&cfg.KeyFile, "tls.key", "", "Path to client key file")
	
	flag.StringVar(&cfg.StorageType, "storage", "cassandra", "The type of storage for checking probe")

	// Cassandra specific configuration
	flag.StringVar(&cfg.CassandraHost, "cassandra.host", "", "The host for probe")
	flag.IntVar(&cfg.CassandraPort, "cassandra.port", 0, "The port for probe")
	flag.StringVar(&cfg.CassandraKeyspace, "cassandra.keyspace", "jaeger", "Keyspace for the Cassandra database")
	flag.StringVar(&cfg.CassandraDatacenter, "cassandra.datacenter", "datacenter1", "Datacenter for the Cassandra database")
	flag.StringVar(&cfg.CassandraTestTable, "cassandra.table", "service_names", "Table name for getting test data from the Cassandra database")
	flag.StringVar(&cfg.CassandraUsername, "cassandra.username", "", "Username for storage authentication")
	flag.StringVar(&cfg.CassandraPassword, "cassandra.password", "", "Password for storage authentication")

	// OpenSearch specific configuration
	flag.StringVar(&cfg.OpenSearchHost, "os.host", "", "The host for probe")
	flag.IntVar(&cfg.OpenSearchPort, "os.port", 0, "The port for probe")
	flag.StringVar(&cfg.OpenSearchIndex, "os.index", "jaeger-span", "Index name for the OpenSearch database")
	flag.StringVar(&cfg.OpenSearchUsername, "os.username", "", "Username for storage authentication")
	flag.StringVar(&cfg.OpenSearchPassword, "os.password", "", "Password for storage authentication")

	flag.Parse()

	// Validate required fields
	if cfg.TLSEnabled && (cfg.CAFile == "" || cfg.CertFile == "" || cfg.KeyFile == "") {
		slog.Error("Missing required TLS certificate files")
		os.Exit(1)
	}

	return cfg
}

// CreateTLSConfig creates a TLS configuration from the provided certificate files
func (c *Config) CreateTLSConfig() *tls.Config {
	if !c.TLSEnabled {
		return nil
	}

	cert, err := tls.LoadX509KeyPair(c.CertFile, c.KeyFile)
	if err != nil {
		slog.Error("Failed to load TLS certificate", "error", err)
		os.Exit(1)
	}

	caCert, err := os.ReadFile(c.CAFile)
	if err != nil {
		slog.Error("Failed to read CA certificate", "error", err)
		os.Exit(1)
	}

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCert) {
		slog.Error("Failed to append CA certificate")
		os.Exit(1)
	}

	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      caCertPool,
	}
}
