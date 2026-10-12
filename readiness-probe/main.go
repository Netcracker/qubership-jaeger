package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
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

// credentialsReader returns the storage credentials. Tests replace the reader that calls Kubernetes.
type credentialsReader func(ctx context.Context, cfg *config.Config) (probes.Credentials, error)

func main() {
	slog.SetDefault(Logger)
	slog.Info("Starting the service")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	// Restore the default signal handling after the first signal, so that a second one stops the process at once.
	context.AfterFunc(ctx, stop)

	err := run(ctx, os.Args[1:], os.Stderr, readCredentials)
	stop()
	if err != nil && !errors.Is(err, flag.ErrHelp) {
		slog.Error("The service failed", "error", err)
		os.Exit(1)
	}
}

// run starts the probe service with the command-line arguments args and blocks until ctx is canceled.
func run(ctx context.Context, args []string, output io.Writer, readCreds credentialsReader) error {
	cfg, err := config.Parse(args, output)
	if err != nil {
		return fmt.Errorf("invalid configuration: %w", err)
	}
	creds, err := readCreds(ctx, cfg)
	if err != nil {
		return err
	}
	probe, err := newProbe(ctx, cfg, creds)
	if err != nil {
		return fmt.Errorf("failed to initialize the probe: %w", err)
	}

	listener, err := net.Listen("tcp", "0.0.0.0:"+strconv.Itoa(cfg.ServicePort))
	if err != nil {
		return fmt.Errorf("failed to listen on port %d: %w", cfg.ServicePort, err)
	}
	s := &Server{probe: probe}
	return s.serve(ctx, listener, cfg.ShutdownTimeout)
}

func newProbe(ctx context.Context, cfg *config.Config, creds probes.Credentials) (probes.Probe, error) {
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

// serve answers HTTP requests on listener and runs the health checks until ctx is canceled.
// Then it shuts the HTTP server down within shutdownTimeout. It closes listener before it returns.
func (s *Server) serve(ctx context.Context, listener net.Listener, shutdownTimeout time.Duration) error {
	server := &http.Server{Handler: s.handler()}
	serveErr := make(chan error, 1)
	go func() {
		slog.Info("The service is listening", "address", listener.Addr().String())
		serveErr <- server.Serve(listener)
	}()

	go s.runHealthChecks(ctx, checkInterval)

	select {
	case err := <-serveErr:
		return fmt.Errorf("the HTTP server failed: %w", err)
	case <-ctx.Done():
	}

	slog.Info("Shutting down gracefully, press Ctrl+C again to force")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("failed to shut down the HTTP server: %w", err)
	}
	return nil
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
