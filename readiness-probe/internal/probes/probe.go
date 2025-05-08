package probes

import (
	"context"
	"fmt"
	"time"
)

// Probe defines the interface for storage health checks
type Probe interface {
	// Check performs the health check and returns true if healthy, false otherwise
	Check(ctx context.Context) bool
	// Name returns the name of the probe
	Name() string
}

// BaseProbeConfig holds common configuration for all probes
type BaseProbeConfig struct {
	MaxRetries          int
	Timeout             time.Duration
	TLSEnabled          bool
	CAFile              string
	CertFile            string
	KeyFile             string
}

// ProbeConfig is the interface for probe-specific configurations
type ProbeConfig interface {
	GetBaseConfig() *BaseProbeConfig
}

// NewProbe creates a new probe based on the storage type
func NewProbe(storageType string, cfg ProbeConfig) (Probe, error) {
	switch storageType {
	case "cassandra":
		if cassandraCfg, ok := cfg.(*CassandraConfig); ok {
			return NewCassandraProbeFromConfig(cassandraCfg)
		}
		return nil, fmt.Errorf("invalid configuration type for Cassandra probe")
	case "opensearch":
		if osCfg, ok := cfg.(*OpenSearchConfig); ok {
			return NewOpenSearchProbeFromConfig(osCfg)
		}
		return nil, fmt.Errorf("invalid configuration type for OpenSearch probe")
	default:
		return nil, fmt.Errorf("unsupported storage type: %s", storageType)
	}
}
