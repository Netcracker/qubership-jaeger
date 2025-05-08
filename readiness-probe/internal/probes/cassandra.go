package probes

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/gocql/gocql"
)

// CassandraProbe implements the Probe interface for Cassandra
type CassandraProbe struct {
	session    *gocql.Session
	keyspace   string
	testTable  string
	maxRetries int
	retryDelay time.Duration
}

// CassandraConfig extends BaseProbeConfig with Cassandra-specific settings
type CassandraConfig struct {
	*BaseProbeConfig
	Host       string
	Port       int
	Keyspace   string
	Datacenter string
	TestTable  string
	Username   string
	Password   string
}

// GetBaseConfig implements the ProbeConfig interface
func (c *CassandraConfig) GetBaseConfig() *BaseProbeConfig {
	return c.BaseProbeConfig
}

// NewCassandraProbeFromConfig creates a new Cassandra probe from configuration
func NewCassandraProbeFromConfig(cfg *CassandraConfig) (*CassandraProbe, error) {
	cluster := gocql.NewCluster(cfg.Host)
	cluster.Port = cfg.Port
	cluster.Keyspace = cfg.Keyspace
	cluster.ConnectTimeout = cfg.Timeout
	cluster.NumConns = 1

	if cfg.TLSEnabled {
		cluster.SslOpts = &gocql.SslOptions{
			CertPath:               cfg.CertFile,
			CaPath:                 cfg.CAFile,
			KeyPath:                cfg.KeyFile,
			EnableHostVerification: true,
		}
	}

	cluster.Authenticator = gocql.PasswordAuthenticator{
		Username: cfg.Username,
		Password: cfg.Password,
	}

	cluster.PoolConfig.HostSelectionPolicy = gocql.DCAwareRoundRobinPolicy(cfg.Datacenter)
	cluster.ProtoVersion = 4
	cluster.Consistency = gocql.Quorum
	cluster.DisableInitialHostLookup = true

	session, err := cluster.CreateSession()
	if err != nil {
		return nil, fmt.Errorf("failed to create Cassandra session: %w", err)
	}

	return NewCassandraProbe(session, cfg.Keyspace, cfg.TestTable, cfg.MaxRetries, cfg.Timeout), nil
}

// NewCassandraProbe creates a new Cassandra probe
func NewCassandraProbe(session *gocql.Session, keyspace, testTable string, maxRetries int, retryDelay time.Duration) *CassandraProbe {
	return &CassandraProbe{
		session:    session,
		keyspace:   keyspace,
		testTable:  testTable,
		maxRetries: maxRetries,
		retryDelay: retryDelay,
	}
}

// Check implements the Probe interface
func (p *CassandraProbe) Check(ctx context.Context) bool {
	for i := range make([]struct{}, p.maxRetries) {
		select {
		case <-ctx.Done():
			return false
		default:
			if p.session != nil {
				query := p.session.Query(fmt.Sprintf("SELECT * FROM %s.%s limit 1;", p.keyspace, p.testTable))
				if query != nil {
					if err := query.Exec(); err != nil {
						slog.Error("Failed to execute Cassandra query", "error", err)
					} else {
						return true
					}
				}
			}

			if i < p.maxRetries-1 {
				slog.Info("Retrying Cassandra health check", "attempt", i+1, "remaining", p.maxRetries-i-1)
				time.Sleep(p.retryDelay)
			}
		}
	}
	return false
}

// Name implements the Probe interface
func (p *CassandraProbe) Name() string {
	return "cassandra"
}
