package config

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

const (
	StorageCassandra  = "cassandra"
	StorageOpenSearch = "opensearch"
)

// TLS holds the settings for the TLS connection to the storage.
type TLS struct {
	Enabled bool
	// InsecureSkipVerify disables server certificate verification. The certificate files are not used in this mode.
	InsecureSkipVerify bool
	CAFile             string
	CertFile           string
	KeyFile            string
}

// Config holds the probe settings parsed from the command line.
type Config struct {
	ServicePort     int
	ShutdownTimeout time.Duration

	// Storage is either StorageCassandra or StorageOpenSearch.
	Storage string
	// Host is a host name for Cassandra and a URL with a scheme for OpenSearch.
	Host string
	Port int

	// MaxErrors is the number of failed attempts after which a check reports the storage as unhealthy.
	MaxErrors int
	// MaxRetries is the number of non-200 responses from OpenSearch after which a check reports it as unhealthy.
	MaxRetries int
	// Timeout limits a single attempt.
	Timeout time.Duration
	// RetryDelay is the pause between two attempts of one check.
	RetryDelay time.Duration

	TLS TLS

	// Namespace and AuthSecretName locate the Secret with the storage credentials.
	Namespace      string
	AuthSecretName string

	Keyspace   string
	Datacenter string
	TestTable  string
}

// Parse reads the configuration from the command-line arguments (without the program name) and validates it.
// It writes the usage and parse errors to output.
func Parse(args []string, output io.Writer) (*Config, error) {
	cfg := &Config{}
	var shutdownTimeout, timeout, retryDelay int

	fs := flag.NewFlagSet("probe", flag.ContinueOnError)
	fs.SetOutput(output)

	// Probe service parameters
	fs.IntVar(&cfg.ServicePort, "servicePort", 8080, "The port the probe service listens on")
	fs.IntVar(&shutdownTimeout, "shutdownTimeout", 5, "The number of seconds for graceful shutdown before connections are canceled")

	// Common parameters
	fs.StringVar(&cfg.Storage, "storage", StorageCassandra, "The type of storage to check: cassandra or opensearch")
	fs.StringVar(&cfg.Host, "host", "", "The Cassandra host or the OpenSearch URL")
	fs.IntVar(&cfg.Port, "port", 0, "The storage port")

	fs.IntVar(&cfg.MaxErrors, "errors", 3, "The number of failed attempts allowed in one check")
	fs.IntVar(&cfg.MaxRetries, "retries", 3, "The number of non-200 OpenSearch responses allowed in one check")
	fs.IntVar(&timeout, "timeout", 5, "The number of seconds after which one attempt fails")
	fs.IntVar(&retryDelay, "retryDelay", 5, "The number of seconds between two attempts of one check")

	fs.BoolVar(&cfg.TLS.Enabled, "tlsEnabled", false, "Enable TLS for the connection to the storage")
	fs.BoolVar(&cfg.TLS.InsecureSkipVerify, "insecureSkipVerify", false, "Disable server certificate verification for TLS")
	fs.StringVar(&cfg.TLS.CAFile, "caPath", "", "The path to the ca-cert.pem file")
	fs.StringVar(&cfg.TLS.CertFile, "crtPath", "", "The path to the client-cert.pem file")
	fs.StringVar(&cfg.TLS.KeyFile, "keyPath", "", "The path to the client-key.pem file")

	// Parameters to fetch the credentials from the Secret
	fs.StringVar(&cfg.Namespace, "namespace", "tracing", "The namespace of the Secret with the storage credentials")
	fs.StringVar(&cfg.AuthSecretName, "authSecretName", "", "The name of the Secret with the username and password values")

	// Cassandra specific parameters
	fs.StringVar(&cfg.Keyspace, "keyspace", "jaeger", "Keyspace for the Cassandra database")
	fs.StringVar(&cfg.Datacenter, "datacenter", "datacenter1", "Datacenter for the Cassandra database")
	fs.StringVar(&cfg.TestTable, "testtable", "service_names", "Table name for getting test data from the Cassandra database")

	if err := fs.Parse(args); err != nil {
		return nil, err
	}

	cfg.Storage = strings.ToLower(cfg.Storage)
	cfg.ShutdownTimeout = time.Duration(shutdownTimeout) * time.Second
	cfg.Timeout = time.Duration(timeout) * time.Second
	cfg.RetryDelay = time.Duration(retryDelay) * time.Second

	if err := cfg.validate(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func (c *Config) validate() error {
	if c.Storage != StorageCassandra && c.Storage != StorageOpenSearch {
		return fmt.Errorf("unsupported value %q of the argument -storage, expected %q or %q", c.Storage, StorageCassandra, StorageOpenSearch)
	}
	if c.Host == "" {
		return errors.New("missing required argument -host")
	}
	if c.AuthSecretName == "" {
		return errors.New("missing required argument -authSecretName")
	}
	if c.TLS.Enabled && !c.TLS.InsecureSkipVerify && (c.TLS.CAFile == "" || c.TLS.CertFile == "" || c.TLS.KeyFile == "") {
		return errors.New("missing one of the required arguments -caPath, -crtPath, -keyPath")
	}
	if c.ShutdownTimeout < 0 || c.Timeout < 0 || c.RetryDelay < 0 {
		return errors.New("the arguments -shutdownTimeout, -timeout, and -retryDelay must not be negative")
	}
	return nil
}

// Endpoint returns the storage address: Host, followed by Port when it is set.
func (c *Config) Endpoint() string {
	if c.Port == 0 {
		return c.Host
	}
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}
