package main

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"time"

	"tracing-readiness-probe/internal/config"
	"tracing-readiness-probe/internal/probes"
)

var logger = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

type Server struct {
	cfg        *config.Config
	probe      probes.Probe
	isHealthy  bool
	healthLock sync.RWMutex
}

func main() {
	slog.SetDefault(logger)
	slog.Info("Starting the service")

	cfg := config.LoadConfig()
	s := &Server{
		cfg: cfg,
	}

	// Initialize the appropriate probe
	s.initProbe()

	// Start health check in background
	go s.runHealthCheck()

	// Setup HTTP server
	host := "0.0.0.0:" + strconv.Itoa(cfg.ServicePort)
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.livenessProbe)
	mux.HandleFunc("/ready", s.readinessProbe)

	server := &http.Server{
		Addr:    host,
		Handler: mux,
	}

	// Setup graceful shutdown
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	go func() {
		slog.Info("Server is listening", "address", host)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Server error", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	stop()

	slog.Info("Shutting down gracefully, press Ctrl+C again to force")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), time.Duration(cfg.ShutdownTimeout)*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		slog.Error("Server shutdown error", "error", err)
		os.Exit(1)
	}
}

func (s *Server) initProbe() {
	baseCfg := &probes.BaseProbeConfig{
		MaxRetries: s.cfg.MaxRetries,
		Timeout:    s.cfg.Timeout,
		TLSEnabled: s.cfg.TLSEnabled,
		CAFile:     s.cfg.CAFile,
		CertFile:   s.cfg.CertFile,
		KeyFile:    s.cfg.KeyFile,
	}

	var cfg probes.ProbeConfig
	switch s.cfg.StorageType {
	case "cassandra":
		slog.Info("Initializing Cassandra probe", "host", s.cfg.CassandraHost, "port", s.cfg.CassandraPort)
		cfg = &probes.CassandraConfig{
			BaseProbeConfig: baseCfg,
			Host:            s.cfg.CassandraHost,
			Port:            s.cfg.CassandraPort,
			Keyspace:        s.cfg.CassandraKeyspace,
			Datacenter:      s.cfg.CassandraDatacenter,
			TestTable:       s.cfg.CassandraTestTable,
			Username:        s.cfg.CassandraUsername,
			Password:        s.cfg.CassandraPassword,
		}
	case "opensearch":
		slog.Info("Initializing OpenSearch probe", "host", s.cfg.OpenSearchHost, "port", s.cfg.OpenSearchPort)
		cfg = &probes.OpenSearchConfig{
			BaseProbeConfig: baseCfg,
			Host:            s.cfg.OpenSearchHost,
			Port:            s.cfg.OpenSearchPort,
			Index:           s.cfg.OpenSearchIndex,
			Username:        s.cfg.OpenSearchUsername,
			Password:        s.cfg.OpenSearchPassword,
		}
	}

	var err error
	s.probe, err = probes.NewProbe(s.cfg.StorageType, cfg)
	if err != nil {
		slog.Error("Failed to initialize probe", "error", err)
		os.Exit(1)
	}
}

func (s *Server) runHealthCheck() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	ctx := context.Background()
	for {
		select {
		case <-ticker.C:
			healthy := s.probe.Check(ctx)
			s.healthLock.Lock()
			s.isHealthy = healthy
			s.healthLock.Unlock()
			slog.Info("Health check completed", "healthy", healthy, "probe", s.probe.Name())
		}
	}
}

func (s *Server) livenessProbe(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Header().Set("Content-Type", "application/text")
	_, err := io.WriteString(w, http.StatusText(http.StatusOK))
	if err != nil {
		slog.Error("Failed to send response", "error", err)
	}
}

func (s *Server) readinessProbe(w http.ResponseWriter, _ *http.Request) {
	s.healthLock.RLock()
	healthy := s.isHealthy
	s.healthLock.RUnlock()

	if healthy {
		w.WriteHeader(http.StatusOK)
		w.Header().Set("Content-Type", "application/text")
		_, err := io.WriteString(w, http.StatusText(http.StatusOK))
		if err != nil {
			slog.Error("Failed to send response", "error", err)
		}
	} else {
		slog.Error("Readiness probe failed")
		w.WriteHeader(http.StatusInternalServerError)
	}
}
