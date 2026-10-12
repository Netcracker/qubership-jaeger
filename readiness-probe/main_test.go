package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
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

func waitFor(t *testing.T, ch <-chan struct{}) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the health check loop")
	}
}
