package probes

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/apache/cassandra-gocql-driver/v2"

	"tracing-readiness-probe/internal/config"
)

// sessionRetryDelay is the pause between two attempts to create a Cassandra session.
const sessionRetryDelay = time.Second

// queryExecutor runs a CQL statement. It hides gocql.Session so that tests can replace it.
type queryExecutor interface {
	Exec(ctx context.Context, stmt string) error
}

type gocqlExecutor struct {
	session *gocql.Session
}

func (e *gocqlExecutor) Exec(ctx context.Context, stmt string) error {
	return e.session.Query(stmt).ExecContext(ctx)
}

// CassandraProbe checks Cassandra by selecting one row from the test table.
type CassandraProbe struct {
	executor    queryExecutor
	stmt        string
	maxAttempts int
	timeout     time.Duration
	retryDelay  time.Duration
}

// NewCassandraProbe connects to Cassandra and returns a probe for it.
// It tries to create the session cfg.MaxErrors times before it returns an error.
func NewCassandraProbe(ctx context.Context, cfg *config.Config, creds Credentials) (*CassandraProbe, error) {
	cluster := newCassandraCluster(cfg, creds)
	session, err := createSessionWithRetry(ctx, cluster.CreateSession, cfg.MaxErrors, sessionRetryDelay)
	if err != nil {
		return nil, err
	}
	return newCassandraProbe(&gocqlExecutor{session: session}, cfg), nil
}

func newCassandraProbe(executor queryExecutor, cfg *config.Config) *CassandraProbe {
	return &CassandraProbe{
		executor:    executor,
		stmt:        fmt.Sprintf("SELECT * FROM %s.%s limit 1;", cfg.Keyspace, cfg.TestTable),
		maxAttempts: cfg.MaxErrors,
		timeout:     cfg.Timeout,
		retryDelay:  cfg.RetryDelay,
	}
}

func newCassandraCluster(cfg *config.Config, creds Credentials) *gocql.ClusterConfig {
	cluster := gocql.NewCluster(cfg.Host)
	cluster.Port = cfg.Port
	cluster.Keyspace = cfg.Keyspace
	cluster.ConnectTimeout = cfg.Timeout
	cluster.NumConns = 1
	if cfg.TLS.Enabled {
		if cfg.TLS.InsecureSkipVerify {
			cluster.SslOpts = &gocql.SslOptions{EnableHostVerification: false}
		} else {
			cluster.SslOpts = &gocql.SslOptions{
				CertPath:               cfg.TLS.CertFile,
				CaPath:                 cfg.TLS.CAFile,
				KeyPath:                cfg.TLS.KeyFile,
				EnableHostVerification: true,
			}
		}
	}
	cluster.Authenticator = gocql.PasswordAuthenticator{
		Username: creds.Username,
		Password: creds.Password,
	}
	cluster.PoolConfig.HostSelectionPolicy = gocql.DCAwareRoundRobinPolicy(cfg.Datacenter)
	cluster.ProtoVersion = 4
	cluster.Consistency = gocql.Quorum
	cluster.DisableInitialHostLookup = true
	return cluster
}

func createSessionWithRetry(ctx context.Context, create func() (*gocql.Session, error), maxAttempts int, retryDelay time.Duration) (*gocql.Session, error) {
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		session, err := create()
		if err == nil {
			return session, nil
		}
		slog.Error("Failed to create Cassandra session", "attempt", attempt, "error", err)
		if attempt < maxAttempts && !wait(ctx, retryDelay) {
			return nil, ctx.Err()
		}
	}
	return nil, fmt.Errorf("failed to create Cassandra session after %d attempts", maxAttempts)
}

// Check implements the Probe interface.
func (p *CassandraProbe) Check(ctx context.Context) bool {
	for attempt := 1; attempt <= p.maxAttempts; attempt++ {
		err := p.exec(ctx)
		if err == nil {
			return true
		}
		slog.Error("Failed to select from the Cassandra test table", "error", err, "remainingAttempts", p.maxAttempts-attempt)
		if attempt < p.maxAttempts && !wait(ctx, p.retryDelay) {
			return false
		}
	}
	return false
}

func (p *CassandraProbe) exec(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, p.timeout)
	defer cancel()
	return p.executor.Exec(ctx, p.stmt)
}

// Name implements the Probe interface.
func (p *CassandraProbe) Name() string {
	return config.StorageCassandra
}
