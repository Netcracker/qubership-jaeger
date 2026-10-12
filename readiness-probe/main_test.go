package main

import (
	"context"
	"errors"
	"flag"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"tracing-readiness-probe/internal/config"
	"tracing-readiness-probe/internal/probes"
)

// fakeProbe reports the results sent to it and signals each call to Check.
type fakeProbe struct {
	results chan bool
	checked chan struct{}
}

func newFakeProbe() *fakeProbe {
	return &fakeProbe{results: make(chan bool), checked: make(chan struct{}, 10)}
}

func (p *fakeProbe) Check(ctx context.Context) bool {
	p.checked <- struct{}{}
	select {
	case result := <-p.results:
		return result
	case <-ctx.Done():
		return false
	}
}

func (p *fakeProbe) Name() string {
	return "fake"
}

func get(t *testing.T, s *Server, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	s.handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestLivenessProbe(t *testing.T) {
	rec := get(t, &Server{}, "/livez")

	if rec.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "text/plain" {
		t.Errorf("expected Content-Type text/plain, got %q", got)
	}
	if rec.Body.String() != "OK" {
		t.Errorf("expected body OK, got %q", rec.Body.String())
	}
}

func TestReadinessProbeHealthy(t *testing.T) {
	s := &Server{}
	s.healthy.Store(true)

	rec := get(t, s, "/health")

	if rec.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", rec.Code)
	}
}

func TestReadinessProbeUnhealthy(t *testing.T) {
	rec := get(t, &Server{}, "/health")

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", rec.Code)
	}
}

// An unknown path must not fall through to a handler that always succeeds.
func TestUnknownPathReturnsNotFound(t *testing.T) {
	s := &Server{}
	s.healthy.Store(true)

	for _, path := range []string{"/", "/ready"} {
		if rec := get(t, s, path); rec.Code != http.StatusNotFound {
			t.Errorf("expected 404 for %s, got %d", path, rec.Code)
		}
	}
}

func TestRunHealthChecksUpdatesReadiness(t *testing.T) {
	probe := newFakeProbe()
	s := &Server{probe: probe}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		s.runHealthChecks(ctx, time.Millisecond)
		close(done)
	}()

	// The first check starts without waiting for the interval.
	waitFor(t, probe.checked)
	probe.results <- true
	waitFor(t, probe.checked)
	if !s.healthy.Load() {
		t.Error("expected the server to be healthy after a successful check")
	}

	probe.results <- false
	waitFor(t, probe.checked)
	if s.healthy.Load() {
		t.Error("expected the server to be unhealthy after a failed check")
	}

	// A check interrupted by shutdown does not change the state.
	s.healthy.Store(true)
	cancel()
	waitFor(t, done)
	if !s.healthy.Load() {
		t.Error("expected the state to stay unchanged after the context is canceled")
	}
}

// failingWriter is a response writer that cannot send the body.
type failingWriter struct {
	*httptest.ResponseRecorder
}

func (failingWriter) Write([]byte) (int, error) {
	return 0, errors.New("connection closed")
}

// WriteString hides the method of the recorder, which io.WriteString would call instead of Write.
func (w failingWriter) WriteString(body string) (int, error) {
	return w.Write([]byte(body))
}

func TestLivenessProbeSurvivesWriteError(t *testing.T) {
	rec := httptest.NewRecorder()

	(&Server{}).livenessProbe(failingWriter{rec}, httptest.NewRequest(http.MethodGet, "/livez", nil))

	if rec.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", rec.Code)
	}
}

func listenLocal(t *testing.T) net.Listener {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen: %v", err)
	}
	return listener
}

func TestServeAnswersRequestsUntilContextIsCanceled(t *testing.T) {
	probe := newFakeProbe()
	s := &Server{probe: probe}
	listener := listenLocal(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	served := make(chan error, 1)
	go func() { served <- s.serve(ctx, listener, 5*time.Second) }()

	waitFor(t, probe.checked)
	probe.results <- true
	for deadline := time.Now().Add(5 * time.Second); !s.healthy.Load(); time.Sleep(time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for the first health check result")
		}
	}

	resp, err := http.Get("http://" + listener.Addr().String() + "/health")
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	if err := resp.Body.Close(); err != nil {
		t.Errorf("failed to close the response body: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}

	cancel()
	select {
	case err := <-served:
		if err != nil {
			t.Errorf("expected a clean shutdown, got %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the shutdown")
	}
}

func TestServeReturnsServerError(t *testing.T) {
	listener := listenLocal(t)
	if err := listener.Close(); err != nil {
		t.Fatalf("failed to close the listener: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	s := &Server{probe: newFakeProbe()}
	if err := s.serve(ctx, listener, time.Second); err == nil {
		t.Fatal("expected an error for a closed listener, got nil")
	}
}

func staticCredentials(context.Context, *config.Config) (probes.Credentials, error) {
	return probes.Credentials{Username: "user", Password: "pass"}, nil
}

// canceledContext makes run shut down as soon as the service is up.
func canceledContext() context.Context {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	return ctx
}

func TestRunStartsAndShutsDown(t *testing.T) {
	args := []string{"-storage=opensearch", "-host=http://opensearch:9200", "-authSecretName=auth", "-servicePort=0"}

	if err := run(canceledContext(), args, io.Discard, staticCredentials); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRunReturnsHelpError(t *testing.T) {
	err := run(canceledContext(), []string{"-h"}, io.Discard, staticCredentials)

	if !errors.Is(err, flag.ErrHelp) {
		t.Errorf("expected flag.ErrHelp, got %v", err)
	}
}

func TestRunFails(t *testing.T) {
	busy := listenLocal(t)
	t.Cleanup(func() { _ = busy.Close() })
	busyPort := strconv.Itoa(busy.Addr().(*net.TCPAddr).Port)

	free := listenLocal(t)
	freePort := strconv.Itoa(free.Addr().(*net.TCPAddr).Port)
	if err := free.Close(); err != nil {
		t.Fatalf("failed to close the listener: %v", err)
	}

	failingCredentials := func(context.Context, *config.Config) (probes.Credentials, error) {
		return probes.Credentials{}, errors.New("no secret")
	}
	openSearch := []string{"-storage=opensearch", "-host=http://opensearch:9200", "-authSecretName=auth"}

	tests := []struct {
		name      string
		args      []string
		readCreds credentialsReader
	}{
		{"invalid configuration", []string{"-storage=opensearch"}, staticCredentials},
		{"unreadable credentials", openSearch, failingCredentials},
		{
			"unreachable Cassandra",
			[]string{"-host=127.0.0.1", "-port=" + freePort, "-authSecretName=auth", "-errors=1", "-timeout=1"},
			staticCredentials,
		},
		{"busy service port", append([]string{"-servicePort=" + busyPort}, openSearch...), staticCredentials},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := run(canceledContext(), tt.args, io.Discard, tt.readCreds); err == nil {
				t.Fatal("expected an error, got nil")
			}
		})
	}
}

func waitFor(t *testing.T, ch <-chan struct{}) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the health check loop")
	}
}
