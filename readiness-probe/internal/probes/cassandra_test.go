package probes

import (
	"context"
	"errors"
	"net"
	"testing"
	"time"

	"github.com/apache/cassandra-gocql-driver/v2"

	"tracing-readiness-probe/internal/config"
)

// fakeExecutor returns the queued errors one by one and nil after the queue is empty.
// Like a real session, it fails when the context is already done.
type fakeExecutor struct {
	errs        []error
	calls       int
	stmt        string
	hasDeadline bool
}

func (f *fakeExecutor) Exec(ctx context.Context, stmt string) error {
	f.calls++
	f.stmt = stmt
	_, f.hasDeadline = ctx.Deadline()
	if err := ctx.Err(); err != nil {
		return err
	}
	if len(f.errs) == 0 {
		return nil
	}
	err := f.errs[0]
	f.errs = f.errs[1:]
	return err
}

func cassandraTestConfig() *config.Config {
	return &config.Config{
		Host:       "cassandra.svc",
		Port:       9042,
		Keyspace:   "jaeger",
		TestTable:  "service_names",
		Datacenter: "dc1",
		MaxErrors:  3,
		Timeout:    time.Second,
		RetryDelay: time.Millisecond,
	}
}

func TestCassandraCheckSucceedsOnFirstAttempt(t *testing.T) {
	executor := &fakeExecutor{}
	probe := newCassandraProbe(executor, cassandraTestConfig())

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result")
	}
	if executor.calls != 1 {
		t.Errorf("expected 1 query, got %d", executor.calls)
	}
	if want := "SELECT * FROM jaeger.service_names limit 1;"; executor.stmt != want {
		t.Errorf("expected statement %q, got %q", want, executor.stmt)
	}
	if !executor.hasDeadline {
		t.Error("expected the query context to have a deadline")
	}
}

// A zero timeout must not turn into a deadline that has already expired.
func TestCassandraCheckWithoutTimeout(t *testing.T) {
	cfg := cassandraTestConfig()
	cfg.Timeout = 0
	executor := &fakeExecutor{}
	probe := newCassandraProbe(executor, cfg)

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result")
	}
	if executor.calls != 1 {
		t.Errorf("expected 1 query, got %d", executor.calls)
	}
	if executor.hasDeadline {
		t.Error("expected the query context to have no deadline")
	}
}

func TestCassandraCheckRetriesAfterError(t *testing.T) {
	executor := &fakeExecutor{errs: []error{errors.New("unavailable"), errors.New("unavailable")}}
	probe := newCassandraProbe(executor, cassandraTestConfig())

	if !probe.Check(context.Background()) {
		t.Fatal("expected a healthy result after retries")
	}
	if executor.calls != 3 {
		t.Errorf("expected 3 queries, got %d", executor.calls)
	}
}

func TestCassandraCheckFailsAfterMaxErrors(t *testing.T) {
	err := errors.New("unavailable")
	executor := &fakeExecutor{errs: []error{err, err, err, err}}
	probe := newCassandraProbe(executor, cassandraTestConfig())

	if probe.Check(context.Background()) {
		t.Fatal("expected an unhealthy result")
	}
	if executor.calls != 3 {
		t.Errorf("expected 3 queries, got %d", executor.calls)
	}
}

func TestCassandraCheckStopsWhenContextIsCanceled(t *testing.T) {
	cfg := cassandraTestConfig()
	cfg.RetryDelay = time.Hour
	executor := &fakeExecutor{errs: []error{errors.New("unavailable")}}
	probe := newCassandraProbe(executor, cfg)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	if probe.Check(ctx) {
		t.Fatal("expected an unhealthy result")
	}
	if executor.calls != 1 {
		t.Errorf("expected 1 query, got %d", executor.calls)
	}
}

func TestCassandraProbeName(t *testing.T) {
	probe := newCassandraProbe(&fakeExecutor{}, cassandraTestConfig())

	if probe.Name() != config.StorageCassandra {
		t.Errorf("expected name %q, got %q", config.StorageCassandra, probe.Name())
	}
}

func TestNewCassandraProbeFailsWhenCassandraIsUnreachable(t *testing.T) {
	cfg := cassandraTestConfig()
	cfg.Host = "127.0.0.1"
	cfg.Port = closedPort(t)
	cfg.MaxErrors = 1

	if _, err := NewCassandraProbe(context.Background(), cfg, Credentials{}); err == nil {
		t.Fatal("expected an error, got nil")
	}
}

// closedPort returns a local port that nothing listens on.
func closedPort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen: %v", err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	if err := listener.Close(); err != nil {
		t.Fatalf("failed to close the listener: %v", err)
	}
	return port
}

func TestNewCassandraClusterWithVerifiedTLS(t *testing.T) {
	cfg := cassandraTestConfig()
	cfg.TLS = config.TLS{Enabled: true, CAFile: "ca.pem", CertFile: "cert.pem", KeyFile: "key.pem"}

	cluster := newCassandraCluster(cfg, Credentials{Username: "user", Password: "pass"})

	if cluster.Port != 9042 || cluster.Keyspace != "jaeger" || cluster.ConnectTimeout != time.Second {
		t.Errorf("unexpected cluster settings: port=%d keyspace=%q timeout=%s", cluster.Port, cluster.Keyspace, cluster.ConnectTimeout)
	}
	if cluster.SslOpts == nil {
		t.Fatal("expected TLS options")
	}
	if !cluster.SslOpts.EnableHostVerification {
		t.Error("expected host verification to be enabled")
	}
	if cluster.SslOpts.CaPath != "ca.pem" || cluster.SslOpts.CertPath != "cert.pem" || cluster.SslOpts.KeyPath != "key.pem" {
		t.Errorf("unexpected certificate paths: %+v", cluster.SslOpts)
	}
	auth, ok := cluster.Authenticator.(gocql.PasswordAuthenticator)
	if !ok || auth.Username != "user" || auth.Password != "pass" {
		t.Errorf("unexpected authenticator: %+v", cluster.Authenticator)
	}
}

func TestNewCassandraClusterWithInsecureTLS(t *testing.T) {
	cfg := cassandraTestConfig()
	cfg.TLS = config.TLS{Enabled: true, InsecureSkipVerify: true, CAFile: "ca.pem"}

	cluster := newCassandraCluster(cfg, Credentials{})

	if cluster.SslOpts == nil {
		t.Fatal("expected TLS options")
	}
	if cluster.SslOpts.EnableHostVerification || cluster.SslOpts.CaPath != "" {
		t.Errorf("expected no verification and no certificate paths, got %+v", cluster.SslOpts)
	}
}

func TestNewCassandraClusterWithoutTLS(t *testing.T) {
	cluster := newCassandraCluster(cassandraTestConfig(), Credentials{})
	if cluster.SslOpts != nil {
		t.Errorf("expected no TLS options, got %+v", cluster.SslOpts)
	}
}

func TestCreateSessionWithRetry(t *testing.T) {
	t.Run("returns the session after a failed attempt", func(t *testing.T) {
		want := &gocql.Session{}
		calls := 0
		create := func() (*gocql.Session, error) {
			calls++
			if calls == 1 {
				return nil, errors.New("unavailable")
			}
			return want, nil
		}

		got, err := createSessionWithRetry(context.Background(), create, 3, time.Millisecond)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != want || calls != 2 {
			t.Errorf("expected the session on attempt 2, got session=%p calls=%d", got, calls)
		}
	})

	t.Run("fails after the last attempt", func(t *testing.T) {
		calls := 0
		create := func() (*gocql.Session, error) {
			calls++
			return nil, errors.New("unavailable")
		}

		if _, err := createSessionWithRetry(context.Background(), create, 2, time.Millisecond); err == nil {
			t.Fatal("expected an error, got nil")
		}
		if calls != 2 {
			t.Errorf("expected 2 attempts, got %d", calls)
		}
	})

	t.Run("stops when the context is canceled", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		create := func() (*gocql.Session, error) { return nil, errors.New("unavailable") }

		_, err := createSessionWithRetry(ctx, create, 3, time.Hour)
		if !errors.Is(err, context.Canceled) {
			t.Errorf("expected context.Canceled, got %v", err)
		}
	})
}
