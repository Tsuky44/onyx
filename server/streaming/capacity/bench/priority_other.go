//go:build !linux && !darwin

package bench

func lowerPriority(int) {}
