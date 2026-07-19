package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const instanceLockDirEnv = "CC_INSTANCE_LOCK_DIR"

func instanceLockPath(configPath string) (string, string) {
	lockDir := filepath.Dir(configPath)
	if override := strings.TrimSpace(os.Getenv(instanceLockDirEnv)); override != "" {
		lockDir = override
	}
	lockName := fmt.Sprintf(".%s.lock", filepath.Base(configPath))
	return lockDir, filepath.Join(lockDir, lockName)
}
