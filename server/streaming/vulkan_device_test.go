package streaming

import (
	"errors"
	"os/exec"
	"reflect"
	"testing"
	"time"
)

func resetVulkanChoice(t *testing.T) {
	t.Helper()
	previous := vulkanChosen.Load()
	vulkanChosen.Store(nil)
	t.Cleanup(func() { vulkanChosen.Store(previous) })
}

// La liste telle que FFmpeg 8.1 l'écrit en `verbose`. La ligne « selected »
// qui la suit n'est pas un périphérique de plus.
const vulkanListing = `[AVHWDeviceContext @ 0x5639ff0d0e80] GPU listing:
[AVHWDeviceContext @ 0x5639ff0d0e80]     0: llvmpipe (LLVM 20.1.2, 256 bits) (software) (0x0)
[AVHWDeviceContext @ 0x5639ff0d0e80]     1: Intel(R) UHD Graphics 630 (CML GT2) (integrated) (0x9bc5)
[AVHWDeviceContext @ 0x5639ff0d0e80] Device 0 selected: llvmpipe (LLVM 20.1.2, 256 bits) (software) (0x0)
[AVHWDeviceContext @ 0x5639ff0d0e80] Queue families:
`

func TestVulkanListingIsParsed(t *testing.T) {
	want := []vulkanDevice{
		{Index: 0, Name: "llvmpipe (LLVM 20.1.2, 256 bits)", Kind: "software"},
		{Index: 1, Name: "Intel(R) UHD Graphics 630 (CML GT2)", Kind: "integrated"},
	}
	if got := parseVulkanDevices(vulkanListing); !reflect.DeepEqual(got, want) {
		t.Errorf("parsed %+v, want %+v", got, want)
	}
	if got := parseVulkanDevices("Device creation failed: -542398533."); len(got) != 0 {
		t.Errorf("a failed device creation lists nothing, got %+v", got)
	}
}

func everySpecWorks(string) error { return nil }

// raceTimes joue le chronomètre : un temps par périphérique.
func raceTimes(times map[string]time.Duration) func(string) (time.Duration, error) {
	return func(spec string) (time.Duration, error) {
		took, ok := times[spec]
		if !ok {
			return 0, errors.New("exit status 1")
		}
		return took, nil
	}
}

func noRace(t *testing.T) func(string) (time.Duration, error) {
	return func(spec string) (time.Duration, error) {
		t.Errorf("%s was raced with nothing to race against", spec)
		return 0, nil
	}
}

// Le serveur qui a motivé ce choix : lavapipe était le périphérique 0 et
// tenait seize threads pour 0,6× le temps réel, à côté d'un circuit libre. Le
// plus rapide à l'essai est retenu, où qu'il soit dans la liste.
func TestTheFasterVulkanDeviceWins(t *testing.T) {
	race := raceTimes(map[string]time.Duration{"vulkan:0": 2 * time.Second, "vulkan:1": 200 * time.Millisecond})
	choice, ok := chooseVulkanDevice(parseVulkanDevices(vulkanListing), "", everySpecWorks, race)
	if !ok || choice.Spec != "vulkan:1" || !choice.GPU {
		t.Fatalf("chose %+v, want the integrated GPU at index 1", choice)
	}
	if choice.Fallback != "vulkan:0" {
		t.Errorf("fallback is %q, want the software device", choice.Fallback)
	}
}

// Le choix suit la machine, pas une préférence : sur un serveur dont les
// cœurs rendent plus vite que son circuit, ce sont les cœurs qui sont pris.
func TestManyCoresBeatASlowGPU(t *testing.T) {
	race := raceTimes(map[string]time.Duration{"vulkan:0": 150 * time.Millisecond, "vulkan:1": 900 * time.Millisecond})
	choice, ok := chooseVulkanDevice(parseVulkanDevices(vulkanListing), "", everySpecWorks, race)
	if !ok || choice.Spec != "vulkan:0" || choice.GPU || choice.Fallback != "" {
		t.Errorf("chose %+v, want software Vulkan, which was faster here", choice)
	}
}

// À temps égal le circuit l'emporte : il laisse les cœurs au décodage et à
// l'encodage de la même session.
func TestATieGoesToTheGPU(t *testing.T) {
	race := raceTimes(map[string]time.Duration{"vulkan:0": time.Second, "vulkan:1": time.Second})
	choice, ok := chooseVulkanDevice(parseVulkanDevices(vulkanListing), "", everySpecWorks, race)
	if !ok || choice.Spec != "vulkan:1" {
		t.Errorf("chose %+v, want the GPU on a tie", choice)
	}
}

// Un serveur sans circuit n'a qu'un périphérique : il est pris sans course,
// donc sans une seconde de rendu logiciel de plus à chaque démarrage.
func TestASingleDeviceIsNotRaced(t *testing.T) {
	software := []vulkanDevice{{Index: 0, Name: "llvmpipe", Kind: "software"}}
	choice, ok := chooseVulkanDevice(software, "", everySpecWorks, noRace(t))
	if !ok || choice.Spec != "vulkan:0" || choice.GPU {
		t.Errorf("chose %+v, want the only device there is", choice)
	}
}

// Un circuit qui ne fait pas tourner le filtre laisse la place au rendu
// logiciel : lent, mais l'image a ses vraies couleurs. Pareil s'il passe le
// petit essai et casse à la course.
func TestSoftwareVulkanTakesOverWhenTheGPUCannotRunTheFilter(t *testing.T) {
	onlySoftware := func(spec string) error {
		if spec == "vulkan:0" {
			return nil
		}
		return errors.New("exit status 1")
	}
	choice, ok := chooseVulkanDevice(parseVulkanDevices(vulkanListing), "", onlySoftware, noRace(t))
	if !ok || choice.Spec != "vulkan:0" || choice.GPU || choice.Fallback != "" {
		t.Errorf("chose %+v, want software Vulkan with nothing behind it", choice)
	}

	breaksInTheRace := raceTimes(map[string]time.Duration{"vulkan:0": time.Second})
	choice, ok = chooseVulkanDevice(parseVulkanDevices(vulkanListing), "", everySpecWorks, breaksInTheRace)
	if !ok || choice.Spec != "vulkan:0" || choice.GPU {
		t.Errorf("chose %+v, want software Vulkan after the GPU failed its timed run", choice)
	}
}

func TestNoVulkanDeviceMeansNoLibplacebo(t *testing.T) {
	nothing := func(string) error { return errors.New("exit status 1") }
	if _, ok := chooseVulkanDevice(parseVulkanDevices(vulkanListing), "", nothing, noRace(t)); ok {
		t.Error("libplacebo declared usable with no device that runs it")
	}
	if _, ok := chooseVulkanDevice(nil, "", nothing, noRace(t)); ok {
		t.Error("libplacebo declared usable with no device at all")
	}
}

// Sans liste lisible, le serveur demande ce qu'il a toujours demandé.
func TestUnreadableListingKeepsTheDefaultDevice(t *testing.T) {
	choice, ok := chooseVulkanDevice(nil, "", everySpecWorks, noRace(t))
	if !ok || choice.Spec != "vulkan" || choice.GPU {
		t.Errorf("chose %+v, want the plain default device", choice)
	}
}

// VULKAN_DEVICE nomme le périphérique : rien d'autre n'est essayé, et c'est
// le moyen de revenir au rendu logiciel sans attendre une image du serveur.
func TestVulkanDeviceCanBeForced(t *testing.T) {
	var tried []string
	record := func(spec string) error { tried = append(tried, spec); return nil }
	choice, ok := chooseVulkanDevice(parseVulkanDevices(vulkanListing), "llvmpipe", record, noRace(t))
	if !ok || choice.Spec != "vulkan:llvmpipe" || choice.GPU {
		t.Errorf("chose %+v, want the forced software device", choice)
	}
	if !reflect.DeepEqual(tried, []string{"vulkan:llvmpipe"}) {
		t.Errorf("tried %v, want only the forced device", tried)
	}
	refuses := func(string) error { return errors.New("no such device") }
	if _, ok := chooseVulkanDevice(nil, "7", refuses, noRace(t)); ok {
		t.Error("a forced device that does not run was accepted")
	}
}

func TestVulkanInitArgsFollowTheChoice(t *testing.T) {
	resetVulkanChoice(t)
	if got := vulkanInitArgs(); !reflect.DeepEqual(got, []string{"-init_hw_device", "vulkan"}) {
		t.Errorf("before any choice the command asks for %v", got)
	}
	vulkanChosen.Store(&vulkanChoice{Spec: "vulkan:1", GPU: true})
	if got := vulkanInitArgs(); !reflect.DeepEqual(got, []string{"-init_hw_device", "vulkan:1"}) {
		t.Errorf("after the choice the command asks for %v", got)
	}
}

// Une session morte sur le circuit avant son premier segment ramène tout le
// serveur au rendu logiciel ; la même sur le rendu logiciel ne change rien.
func TestSessionDyingOnTheGPUFallsBackToSoftwareVulkan(t *testing.T) {
	resetVulkanChoice(t)
	vulkanChosen.Store(&vulkanChoice{Spec: "vulkan:1", GPU: true, Fallback: "vulkan:0"})
	noteVulkanSessionDied("s", "vulkan error")
	if got := vulkanInitArgs(); got[1] != "vulkan:0" || vulkanOnGPU() {
		t.Errorf("after a death on the GPU the command asks for %v", got)
	}
	noteVulkanSessionDied("s", "again")
	if got := vulkanInitArgs(); got[1] != "vulkan:0" {
		t.Errorf("a death on software Vulkan changed the device to %v", got)
	}
}

// L'essai doit passer par le filtre d'une session, pas par un filtre vide.
func TestLibplaceboProbeRunsTheSessionFilter(t *testing.T) {
	args := libplaceboProbeArgs("vulkan:1", "320x240", 2)
	if !hasFlag(args, "-init_hw_device", "vulkan:1") || !hasFlag(args, "-vf", doviToSDRFilter) {
		t.Errorf("probe does not run the session filter on the device: %v", args)
	}
}

// Sur une machine qui a FFmpeg, libplacebo et un pilote Vulkan, le choix réel
// doit désigner un périphérique sur lequel le filtre tourne.
func TestVulkanChoiceWorksOnThisMachine(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("no ffmpeg on this machine")
	}
	devices := listVulkanDevices()
	if len(devices) == 0 {
		t.Skip("no Vulkan device listed on this machine")
	}
	choice, ok := chooseVulkanDevice(devices, "", libplaceboRunsOn, libplaceboRace)
	if !ok {
		t.Skip("no Vulkan device runs libplacebo on this machine")
	}
	took, err := libplaceboRace(choice.Spec)
	if err != nil {
		t.Fatalf("chosen device %q fails the timed run: %v", choice.Spec, err)
	}
	t.Logf("%s: %s for the timed run", choice.Spec, took.Round(time.Millisecond))
}
