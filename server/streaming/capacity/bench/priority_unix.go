//go:build linux || darwin

package bench

import "syscall"

// lowerPriority baisse la priorité d'une mesure lancée en fond, comme les
// aperçus (streaming/previews_priority_unix.go).
func lowerPriority(pid int) {
	_ = syscall.Setpriority(syscall.PRIO_PROCESS, pid, 15)
}
