package probes

import (
	"context"
	"time"
)

// Probe checks the health of a storage.
type Probe interface {
	// Check reports whether the storage is healthy. It returns false when ctx is canceled before an attempt succeeds.
	Check(ctx context.Context) bool
	// Name returns the storage name for logs.
	Name() string
}

// Credentials holds the username and password for the storage.
type Credentials struct {
	Username string
	Password string
}

// wait pauses for d and reports false if ctx is canceled first.
func wait(ctx context.Context, d time.Duration) bool {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
