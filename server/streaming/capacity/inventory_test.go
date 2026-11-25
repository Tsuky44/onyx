package capacity

import (
	"context"
	"errors"
	"reflect"
	"runtime"
	"strings"
	"testing"
	"testing/fstest"
)

func TestCPUModel(t *testing.T) {
	cases := []struct {
		name, cpuinfo, want string
	}{
		{"xeon", "processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz\n\nprocessor\t: 1\nmodel name\t: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz\n",
			"Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz"},
		{"pi4", "processor\t: 0\nBogoMIPS\t: 108.00\nCPU part\t: 0xd08\n\nHardware\t: BCM2835\nRevision\t: c03114\nModel\t\t: Raspberry Pi 4 Model B Rev 1.4\n",
			"Raspberry Pi 4 Model B Rev 1.4"},
		{"arm sans Model", "processor : 0\nHardware : Rockchip RK3588\n", "Rockchip RK3588"},
		{"vide", "", ""},
	}
	for _, c := range cases {
		if got := cpuModel(c.cpuinfo); got != c.want {
			t.Errorf("%s : %q, voulu %q", c.name, got, c.want)
		}
	}
}

func TestUsableMemory(t *testing.T) {
	const meminfo = "MemTotal:       16318432 kB\nMemFree:         1234567 kB\n"
	host := int64(16318432) * 1024
	cases := []struct {
		name, v2, v1, meminfo string
		want                  int64
	}{
		{"cgroup v2 limité", "4294967296\n", "", meminfo, 4294967296},
		{"cgroup v2 sans limite", "max\n", "", meminfo, host},
		{"cgroup v1 limité", "", "2147483648\n", meminfo, 2147483648},
		{"cgroup v1 sans limite", "", "9223372036854771712\n", meminfo, host},
		{"limite au-dessus de la machine", "68719476736", "", meminfo, host},
		{"rien", "", "", "", 0},
	}
	for _, c := range cases {
		if got := usableMemory(c.v2, c.v1, c.meminfo); got != c.want {
			t.Errorf("%s : %d, voulu %d", c.name, got, c.want)
		}
	}
}

func TestParseFFmpegLists(t *testing.T) {
	if got := parseFFmpegVersion("ffmpeg version 6.1.1 Copyright (c) 2000-2023 the FFmpeg developers\nbuilt with gcc"); got != "6.1.1" {
		t.Errorf("version %q", got)
	}
	encoders := ` V..... = Video
 A..... = Audio
 ------
 V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC (codec h264)
 V....D h264_vaapi           H.264/AVC (VAAPI) (codec h264)
 A....D aac                  AAC (Advanced Audio Coding)
`
	if got, want := parseCodecList(encoders), []string{"aac", "h264_vaapi", "libx264"}; !reflect.DeepEqual(got, want) {
		t.Errorf("encodeurs %v, voulu %v", got, want)
	}
	filters := `Filters:
  T.. = Timeline support
  .S. = Slice threading
 ... abench            A->A       Benchmark part of a filtergraph.
 TSC zscale            V->V       Apply resizing, colorspace and bit depth conversion.
 ... libplacebo        N->V       Apply various GPU filters from libplacebo
`
	if got, want := parseFilterList(filters), []string{"abench", "libplacebo", "zscale"}; !reflect.DeepEqual(got, want) {
		t.Errorf("filtres %v, voulu %v", got, want)
	}
	if got, want := parseHWAccels("Hardware acceleration methods:\nvdpau\nvaapi\n\nvulkan\n"), []string{"vaapi", "vdpau", "vulkan"}; !reflect.DeepEqual(got, want) {
		t.Errorf("hwaccels %v, voulu %v", got, want)
	}
}

// Un conteneur bridé avec le circuit Intel et une carte NVIDIA passés : tout
// se lit sous la racine injectée, sans toucher à la machine des tests.
func TestReadInventory_FromAFakeRoot(t *testing.T) {
	root := fstest.MapFS{
		"proc/cpuinfo":             {Data: []byte("model name\t: Intel(R) N100\n")},
		"proc/meminfo":             {Data: []byte("MemTotal: 16000000 kB\n")},
		"sys/fs/cgroup/memory.max": {Data: []byte("8589934592\n")},
		"dev/dri/card0":            {},
		"dev/dri/renderD128":       {},
		"dev/dri/renderD129":       {},
		"dev/nvidia0":              {},
		"dev/nvidiactl":            {},
		"dev/null":                 {},
	}
	run := func(_ context.Context, args ...string) (string, error) {
		switch args[len(args)-1] {
		case "-version":
			return "ffmpeg version 7.1 Copyright\n", nil
		case "-encoders":
			return " ------\n V....D h264_vaapi  VAAPI\n", nil
		case "-filters":
			return " ... scale_vaapi  V->V  Scale\n", nil
		case "-hwaccels":
			return "", errors.New("ffmpeg sans -hwaccels")
		}
		return "", nil
	}
	inv := ReadInventory(context.Background(), root, run)
	want := Inventory{
		Cores:       runtime.GOMAXPROCS(0),
		MemoryBytes: 8589934592,
		Arch:        runtime.GOARCH,
		CPUModel:    "Intel(R) N100",
		RenderNodes: []string{"/dev/dri/renderD128", "/dev/dri/renderD129"},
		NvidiaNodes: []string{"/dev/nvidia0", "/dev/nvidiactl"},
		FFmpeg: FFmpegInventory{
			Version:  "7.1",
			Encoders: []string{"h264_vaapi"},
			Filters:  []string{"scale_vaapi"},
		},
	}
	if !reflect.DeepEqual(inv, want) {
		t.Errorf("inventaire\n%+v\nvoulu\n%+v", inv, want)
	}
	if !inv.FFmpeg.HasEncoder("h264_vaapi") || inv.FFmpeg.HasEncoder("h264_nvenc") {
		t.Error("HasEncoder lit mal la liste")
	}
}

// Une machine sans /proc ni /dev (Windows, macOS en développement) a un
// inventaire pauvre, pas une erreur.
func TestReadInventory_EmptyRoot(t *testing.T) {
	inv := ReadInventory(context.Background(), fstest.MapFS{}, nil)
	if inv.Cores < 1 || inv.CPUModel != "" || inv.RenderNodes != nil || inv.MemoryBytes != 0 {
		t.Errorf("inventaire vide inattendu : %+v", inv)
	}
	if !strings.Contains(runtime.GOARCH, inv.Arch) {
		t.Errorf("arch %q", inv.Arch)
	}
}
