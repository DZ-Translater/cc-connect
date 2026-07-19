//go:build !windows

package main

import (
	"fmt"
	"os"
	"syscall"
)

// InstanceLock provides a file-based exclusive lock to prevent multiple
// cc-connect instances with the same config from running simultaneously.
type InstanceLock struct {
	file     *os.File
	path     string
	acquired bool
}

// AcquireInstanceLock attempts to acquire an exclusive lock for the given config path.
// If another instance is already running with the same config, it returns an error
// containing the PID of the existing instance.
//
// The lock file is placed in the same directory as the config file unless
// CC_INSTANCE_LOCK_DIR overrides it for read-only configuration mounts.
func AcquireInstanceLock(configPath string) (*InstanceLock, error) {
	lockDir, lockPath := instanceLockPath(configPath)

	// Ensure directory exists
	if err := os.MkdirAll(lockDir, 0755); err != nil {
		return nil, fmt.Errorf("cannot create lock directory: %w", err)
	}

	// Open/create the lock file
	f, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		return nil, fmt.Errorf("cannot open lock file: %w", err)
	}

	// Try to acquire exclusive lock (non-blocking)
	err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	if err != nil {
		// Lock is held by another process
		f.Close()

		// Try to read PID from lock file for better error message
		pid := readPIDFromLockFile(lockPath)
		if pid > 0 {
			return nil, fmt.Errorf("another cc-connect instance is already running (PID %d) with config %s", pid, configPath)
		}
		return nil, fmt.Errorf("another cc-connect instance is already running with config %s", configPath)
	}

	// Write our PID to the lock file for diagnostics
	pid := os.Getpid()
	_ = f.Truncate(0)
	_, _ = f.Seek(0, 0)
	fmt.Fprintf(f, "%d\n", pid)

	return &InstanceLock{
		file:     f,
		path:     lockPath,
		acquired: true,
	}, nil
}

// Release releases the instance lock. It is safe to call multiple times.
func (l *InstanceLock) Release() {
	if l == nil || !l.acquired {
		return
	}

	// Remove PID before unlocking
	if l.file != nil {
		_ = l.file.Truncate(0)
		_ = syscall.Flock(int(l.file.Fd()), syscall.LOCK_UN)
		l.file.Close()
		l.file = nil
	}

	l.acquired = false
}

// Path returns the path to the lock file.
func (l *InstanceLock) Path() string {
	return l.path
}

// readPIDFromLockFile attempts to read a PID from a lock file.
// Returns 0 if the PID cannot be determined.
func readPIDFromLockFile(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}

	var pid int
	if _, err := fmt.Sscanf(string(data), "%d", &pid); err != nil {
		return 0
	}

	return pid
}

// KillExistingInstance attempts to kill the process holding the lock for the given config.
// Returns true if a process was killed, false otherwise.
func KillExistingInstance(configPath string) bool {
	_, lockPath := instanceLockPath(configPath)

	pid := readPIDFromLockFile(lockPath)
	if pid <= 0 {
		return false
	}

	// Check if process exists
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}

	// On Unix, FindProcess always succeeds, so we need to signal it
	// to check if it actually exists
	if err := proc.Signal(syscall.Signal(0)); err != nil {
		// Process doesn't exist
		return false
	}

	// Process exists, kill it
	if err := proc.Kill(); err != nil {
		return false
	}

	// Wait a moment for the process to exit
	// Note: we can't use proc.Wait() as we're not the parent
	return true
}
