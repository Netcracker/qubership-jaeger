package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"k8s.io/client-go/kubernetes"
	ctrl "sigs.k8s.io/controller-runtime"

	"tracing-readiness-probe/internal/config"
	"tracing-readiness-probe/internal/probes"
	"tracing-readiness-probe/internal/secret"
)

// checkInterval is the pause between two storage health checks.
const checkInterval = 10 * time.Second

var Logger = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

type Server struct {
	probe   probes.Probe
	healthy atomic.Bool
}

func main() {
	slog.SetDefault(Logger)
	slog.Info("Starting the service")

	cfg, err := config.Parse(os.Args[1:], os.Stderr)
	if errors.Is(err, flag.ErrHelp) {
		os.Exit(0)
	}
	if err != nil {
		slog.Error("Invalid configuration", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	probe, err := newProbe(ctx, cfg)
	if err != nil {
		slog.Error("Failed to initialize the probe", "error", err)
		os.Exit(1)
	}
	s := &Server{probe: probe}

	host := "0.0.0.0:" + strconv.Itoa(cfg.ServicePort)
	server := &http.Server{
		Addr:    host,
		Handler: s.handler(),
	}

	go func() {
		slog.Info("The service is listening", "address", host)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("The HTTP server failed", "error", err)
			os.Exit(1)
		}
	}()

	go s.runHealthChecks(ctx, checkInterval)

	<-ctx.Done()

	stop()
	slog.Info("Shutting down gracefully, press Ctrl+C again to force")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		slog.Error("Failed to shut down the HTTP server", "error", err)
		os.Exit(1)
	}
}

func newProbe(ctx context.Context, cfg *config.Config) (probes.Probe, error) {
	creds, err := readCredentials(ctx, cfg)
	if err != nil {
		return nil, err
	}
	if cfg.Storage == config.StorageOpenSearch {
		return probes.NewOpenSearchProbe(cfg, creds)
	}
	return probes.NewCassandraProbe(ctx, cfg, creds)
}

func readCredentials(ctx context.Context, cfg *config.Config) (probes.Credentials, error) {
	restConfig, err := ctrl.GetConfig()
	if err != nil {
		return probes.Credentials{}, fmt.Errorf("failed to load the Kubernetes client configuration: %w", err)
	}
	client, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return probes.Credentials{}, fmt.Errorf("failed to create the Kubernetes client: %w", err)
	}
	return secret.ReadCredentials(ctx, client, cfg.Namespace, cfg.AuthSecretName)
}

func (s *Server) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.readinessProbe)
	mux.HandleFunc("/livez", s.livenessProbe)
	return mux
}

// runHealthChecks checks the storage right away and then after every interval until ctx is canceled.
func (s *Server) runHealthChecks(ctx context.Context, interval time.Duration) {
	slog.Info("Readiness probe process is starting", "storage", s.probe.Name())
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		healthy := s.probe.Check(ctx)
		if ctx.Err() != nil {
			return
		}
		s.healthy.Store(healthy)
		slog.Info("Health check completed", "healthy", healthy, "storage", s.probe.Name())

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (s *Server) livenessProbe(w http.ResponseWriter, _ *http.Request) {
	writeOK(w)
}

func (s *Server) readinessProbe(w http.ResponseWriter, _ *http.Request) {
	if !s.healthy.Load() {
		slog.Error("Readiness probe failed")
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	writeOK(w)
}

func writeOK(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(http.StatusOK)
	if _, err := io.WriteString(w, http.StatusText(http.StatusOK)); err != nil {
		slog.Error("Failed to send the response", "error", err)
	}
}
