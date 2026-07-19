//go:build !windows

package main

import (
	"path/filepath"
	"testing"
)

func TestAcquireInstanceLock_Success(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.toml")

	lock, err := AcquireInstanceLock(cfg)
	if err != nil {
		t.Fatalf("AcquireInstanceLock: %v", err)
	}
	if lock == nil || !lock.acquired {
		t.Fatal("expected acquired lock")
	}
	defer lock.Release()

	wantPath := filepath.Join(dir, ".config.toml.lock")
	if lock.Path() != wantPath {
		t.Fatalf("lock path = %q, want %q", lock.Path(), wantPath)
	}
}

func TestAcquireInstanceLock_UsesConfiguredLockDir(t *testing.T) {
	configDir := t.TempDir()
	lockDir := filepath.Join(t.TempDir(), "locks")
	cfg := filepath.Join(configDir, "config.toml")
	t.Setenv(instanceLockDirEnv, lockDir)

	lock, err := AcquireInstanceLock(cfg)
	if err != nil {
		t.Fatalf("AcquireInstanceLock: %v", err)
	}
	defer lock.Release()

	wantPath := filepath.Join(lockDir, ".config.toml.lock")
	if lock.Path() != wantPath {
		t.Fatalf("lock path = %q, want %q", lock.Path(), wantPath)
	}
}

func TestAcquireInstanceLock_AlreadyLocked(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.toml")

	first, err := AcquireInstanceLock(cfg)
	if err != nil {
		t.Fatalf("first AcquireInstanceLock: %v", err)
	}
	defer first.Release()

	_, err = AcquireInstanceLock(cfg)
	if err == nil {
		t.Fatal("second AcquireInstanceLock should fail while lock held")
	}
}
