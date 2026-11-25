package streaming

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"project-player/server/safego"
	"project-player/server/streaming/capacity"
)

var (
	errFFmpegDied  = errors.New("ffmpeg process died before producing output")
	errWaitTimeout = errors.New("timeout waiting for transcoder output")
	// segmentsAhead is expressed in segments, so it must track segmentDuration
	// to keep the same ~32s just-in-time buffer.
	segmentsAhead   = 32 / segmentDuration
	throttleEnabled = true
)

// lockedBuffer collects FFmpeg's stderr for later inspection.
//
// os/exec writes to cmd.Stderr from its own goroutine while request goroutines
// read it, which an unguarded bytes.Buffer does not survive. It was a latent
// race while only a failed start read the buffer; /start now inspects it on
// every session — after a 750ms probe, with FFmpeg definitely still running —
// so it is a race that would actually be hit.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// TranscodeSession represents a single active HLS transcoding session.
type TranscodeSession struct {
	TicketHash  [32]byte // binds this HLS session to its playback ticket
	ID          string
	MediaID     int
	Quality     string
	AudioIndex  int // default audio track (0:a:N) for this session
	StartOffset int // seconds into the original media where the HLS timeline begins
	TmpDir      string
	Probe       *ProbeResult
	// MasterPlaylist is the master this session publishes, rendered once at
	// /start from the parameters it was created with. See BuildMasterPlaylist.
	MasterPlaylist string
	// SegmentExt is the extension the muxer writes segments with, ".ts" or
	// ".m4s". The throttler counts segment files by name, so it has to know
	// which name the session is producing; empty means ".ts".
	SegmentExt string
	// Variants est le nombre de séries de segments que la session écrit : la
	// vidéo, puis une par rendition audio. La purge les parcourt toutes.
	Variants int
	// RetainSegments est ce que la session garde derrière le dernier segment
	// demandé ; au-delà, ils sont effacés au fil de la lecture. 0 : tout est
	// gardé, pour un client qui ne sait pas rouvrir une session pour reculer.
	RetainSegments int
	// superseded est posé, sous le verrou du gestionnaire, quand une session
	// plus récente sur le même ticket la remplace. Voir SessionManager.Supersede.
	superseded bool
	// hardwareFilters dit que l'image de cette session reste sur le circuit
	// vidéo (hardware_filters.go) : si FFmpeg meurt avant le premier segment,
	// c'est cette chaîne qui est retirée.
	hardwareFilters bool
	// vulkanGPU dit que le tone mapping de cette session passe par libplacebo
	// sur un vrai circuit (vulkan_device.go), avec la même conséquence.
	vulkanGPU bool
	// hardwareEncoder est l'encodeur du circuit que la mesure a choisi pour
	// cette session, vide sinon : lui aussi est retiré si elle meurt avant
	// son premier segment (recipe_retire.go).
	hardwareEncoder string
	// plan est la recette prévue, nil pour une recopie ou sans profil, et
	// extraCost ce que la session coûte en plus de l'image (l'audio). La
	// session les rapporte au profil avec ce qu'elle a vraiment tenu
	// (session_feedback.go).
	plan      *capacity.Pipeline
	extraCost capacity.Cost
	// ladder est ce que /health sait pour suggérer un barreau
	// (suggest_quality.go) ; nil pour une session posée par un test.
	ladder *ladderContext
	// standby est posé, sous le même verrou, pour une session que le lecteur
	// prépare sans encore la lire : elle ne remplace rien tant que son premier
	// segment n'a pas été demandé. Voir SessionManager.Claim et ADR-0056.
	standby bool
	// reservation est le coût prévu de la session sur chaque ressource, posé
	// par /start ; le gestionnaire le réserve dans son budget (CreateSession).
	reservation capacity.Cost

	ctx    context.Context
	cancel context.CancelFunc
	cmd    *exec.Cmd
	stderr lockedBuffer

	mu     sync.Mutex
	active bool
	paused bool
	// frozen est posé par Freeze : la session est arrêtée (SIGSTOP) pour de bon,
	// et le bridage ne la relance plus jamais. Il implique paused.
	frozen bool
	// cpuUsed est le temps processeur que FFmpeg a consommé, connu à sa sortie
	// seulement. Voir CPUCost.
	cpuUsed time.Duration
	// exited dit que cpuUsed est fixé : FFmpeg est sorti et a été attendu.
	exited               bool
	lastAccess           time.Time
	lastRequestedSegment int
	producedSegments     int
	// purgedBelow est le premier index de segment encore sur le disque.
	purgedBelow int
	// startedAt date le lancement de FFmpeg, et burstSpeed fige sa vitesse au
	// premier arrêt par le bridage : après, il ne tourne plus que par à-coups
	// et le temps écoulé ne mesure plus rien. Voir Health.
	startedAt  time.Time
	burstSpeed float64
	// budget est celui où la réservation est posée, nil tant qu'elle ne l'est
	// pas. Voir session_budget.go.
	budget *capacity.Budget
	// pace suit la vitesse de la session qui tourne (session_pace.go) ;
	// pausedAt et pausedProduced datent la première pause du bridage.
	pace           paceWatch
	pausedAt       time.Time
	pausedProduced int
	// speedReported dit que la vitesse a été rapportée au profil, et
	// speedRatio ce qu'elle a dit (session_feedback.go).
	speedReported bool
	speedRatio    float64
	// suggestion est l'état de suggested_quality (suggest_quality.go).
	suggestion suggestionState
}

// SessionHealth est ce qu'une session dit de son encodeur.
type SessionHealth struct {
	// AheadSeconds est ce que l'encodeur a produit au-delà du dernier segment
	// demandé. Une trentaine de secondes quand il suit ; presque rien quand
	// c'est lui que le lecteur attend.
	AheadSeconds int `json:"ahead_seconds"`
	// Speed est sa vitesse rapportée à celle de la lecture, 0 tant qu'elle
	// n'est pas mesurable : celle qu'il avait en prenant son avance, ou celle
	// qu'il a depuis le début s'il ne l'a jamais prise. Sous 1, aucune ligne
	// ne rendra la lecture fluide.
	Speed float64 `json:"speed"`
	// SuggestedQuality est le barreau que le serveur conseille d'ouvrir :
	// plus bas quand la session ne suit plus la lecture, plus haut quand la
	// marge est revenue, ou le barreau en cours quand une recette plus légère
	// y tient. Le client décide : l'Auto peut y aller, un choix manuel n'en
	// fait qu'un message. Absent quand il n'y a rien à suggérer, et d'un
	// serveur sans profil matériel prêt (suggest_quality.go).
	SuggestedQuality string `json:"suggested_quality,omitempty"`
}

// Health mesure l'avance et la vitesse de l'encodeur à l'instant now.
//
// C'est ce qui distingue, vu du lecteur, une ligne trop lente d'un serveur
// trop lent : les deux vident le tampon, mais descendre en débit ne soulage
// que la première. Voir ADR-0056.
func (s *TranscodeSession) Health(now time.Time) SessionHealth {
	produced := s.countVideoSegments()
	s.mu.Lock()
	defer s.mu.Unlock()
	ahead := (produced - 1 - s.lastRequestedSegment) * segmentDuration
	if ahead < 0 {
		ahead = 0
	}
	return SessionHealth{AheadSeconds: ahead, Speed: s.speedLocked(produced, now)}
}

// speedLocked est la vitesse de l'encodeur ; s.mu est tenu.
func (s *TranscodeSession) speedLocked(produced int, now time.Time) float64 {
	if s.burstSpeed > 0 {
		return s.burstSpeed
	}
	if s.startedAt.IsZero() {
		return 0
	}
	ran := now.Sub(s.startedAt)
	// Sur moins que ça, le démarrage de FFmpeg pèse plus que l'encodage.
	if ran < 3*time.Second {
		return 0
	}
	return float64(produced*segmentDuration) / ran.Seconds()
}

// Start launches FFmpeg and the JIT throttling watchdog.
func (s *TranscodeSession) Start() error {
	s.mu.Lock()
	if err := s.cmd.Start(); err != nil {
		s.mu.Unlock()
		return err
	}
	s.active = true
	s.lastAccess = time.Now()
	s.startedAt = s.lastAccess
	s.mu.Unlock()

	go safego.Run("watch", func() { s.watch() })
	if throttleEnabled {
		go safego.Run("throttle", func() { s.throttle() })
	}
	return nil
}

// watch reaps the process so it never becomes a zombie and records its exit.
func (s *TranscodeSession) watch() {
	err := s.cmd.Wait()
	cpu := processCPUTime(s.cmd.ProcessState)
	s.mu.Lock()
	s.active = false
	s.cpuUsed, s.exited = cpu, true
	// FFmpeg est sorti (film encodé jusqu'au bout, ou mort) : il ne coûte plus.
	s.releaseBudgetLocked()
	s.mu.Unlock()
	// Morte seule (personne ne l'a arrêtée), en erreur, sans avoir rien écrit.
	if !s.diedBeforeFirstSegment(err) {
		return
	}
	if kind, encoder := s.recipeAtFault(); kind != recipeNone {
		retireRecipe(kind, encoder, s.ID, s.stderr.String())
	}
}

// diedBeforeFirstSegment dit que FFmpeg a échoué de lui-même sans produire un
// seul segment : la commande ne tient pas sur cet hôte, ou pas sur ce fichier.
func (s *TranscodeSession) diedBeforeFirstSegment(waitErr error) bool {
	return waitErr != nil && s.ctx.Err() == nil && s.countVideoSegments() == 0
}

// IsActive reports whether the FFmpeg process is still running.
func (s *TranscodeSession) IsActive() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.active
}

// Touch updates the last-access time (called on each playlist/segment request).
func (s *TranscodeSession) Touch() {
	s.mu.Lock()
	s.lastAccess = time.Now()
	s.mu.Unlock()
}

// LastAccess returns the last-access time (used by the idle reaper).
func (s *TranscodeSession) LastAccess() time.Time {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lastAccess
}

// NoteSegment records the highest video segment index the client has fetched.
// The throttler uses it to keep only a small buffer transcoded ahead, so a
// paused or idle client never causes the whole movie to be processed.
func (s *TranscodeSession) NoteSegment(index int) {
	s.mu.Lock()
	if index > s.lastRequestedSegment {
		s.lastRequestedSegment = index
	}
	s.lastAccess = time.Now()
	s.mu.Unlock()
}

// throttle keeps the transcoder at most segmentsAhead segments in front of the
// client's current position by pausing (SIGSTOP) and resuming (SIGCONT) FFmpeg.
// This gives a true sliding-window / just-in-time buffer: CPU and disk are only
// spent on the part of the film the user is actually watching.
func (s *TranscodeSession) throttle() {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			if !s.IsActive() {
				return
			}
			produced := s.countVideoSegments()
			s.purgeBehind()

			s.throttleStep(produced)
			s.afterTick(time.Now(), produced)
		}
	}
}

// throttleStep décide d'arrêter ou de relancer FFmpeg selon l'avance qu'il a
// prise. Le signal part sous s.mu, comme celui de Freeze : sinon un bridage qui
// a lu « pas gelé » relancerait, une fois le gel posé, la session qu'on vient
// d'arrêter.
func (s *TranscodeSession) throttleStep(produced int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.frozen {
		return
	}
	bufferAhead := (produced - 1) - s.lastRequestedSegment
	switch {
	case bufferAhead >= segmentsAhead && !s.paused:
		s.signal(syscall.SIGSTOP)
		s.paused = true
		if s.burstSpeed == 0 {
			s.burstSpeed = s.speedLocked(produced, time.Now())
			s.pausedAt, s.pausedProduced = time.Now(), produced
		}
	case bufferAhead < segmentsAhead && s.paused:
		s.signal(syscall.SIGCONT)
		s.paused = false
	}
}

// Freeze arrête FFmpeg pour de bon (SIGSTOP) : une session remplacée n'a plus
// de lecteur à servir, seulement des segments déjà écrits que le client peut
// encore demander pendant la grâce de Supersede. Sans le gel, elle encodait
// pendant ces trente secondes à côté de celle qui la remplace — sur une machine
// juste assez rapide pour une session, c'est ce qui faisait saccader la nouvelle.
//
// Contrairement à l'arrêt du bridage, le gel survit à l'avance qui retombe :
// throttleStep ne relance jamais une session gelée. Kill la relance quand même
// avant SIGTERM, qu'un processus arrêté ignore.
func (s *TranscodeSession) Freeze() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.frozen || !s.active {
		return
	}
	s.frozen = true
	// Gelée, elle ne prend plus rien : sa part revient aux autres sessions.
	s.releaseBudgetLocked()
	if !s.paused {
		s.signal(syscall.SIGSTOP)
		s.paused = true
		if s.burstSpeed == 0 {
			s.burstSpeed = s.speedLocked(s.producedSegments, time.Now())
		}
	}
}

// Frozen dit que la session a été gelée par Freeze.
func (s *TranscodeSession) Frozen() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.frozen
}

// countVideoSegments returns how many .ts segments of the video rendition have
// been produced.
//
// Segments are numbered sequentially and never removed, so this walks forward
// from the last known count instead of re-reading the whole directory. The old
// full ReadDir ran once per second per session over a directory that reaches
// thousands of entries on a feature-length film.
func (s *TranscodeSession) countVideoSegments() int {
	s.mu.Lock()
	n := s.producedSegments
	s.mu.Unlock()

	ext := s.segmentExt()
	for {
		path := filepath.Join(s.TmpDir, fmt.Sprintf("stream_0_%03d%s", n, ext))
		if _, err := os.Stat(path); err != nil {
			break
		}
		n++
	}

	s.mu.Lock()
	if n > s.producedSegments {
		s.producedSegments = n
	}
	n = s.producedSegments
	s.mu.Unlock()
	return n
}

// purgeBehind efface les segments plus vieux que RetainSegments derrière le
// dernier demandé, dans toutes les séries. Le client qui a demandé la purge
// ouvre une nouvelle session pour reculer plus loin.
func (s *TranscodeSession) purgeBehind() {
	if s.RetainSegments <= 0 {
		return
	}
	s.mu.Lock()
	from := s.purgedBelow
	to := s.lastRequestedSegment - s.RetainSegments
	s.mu.Unlock()
	if to <= from {
		return
	}
	variants := s.Variants
	if variants < 1 {
		variants = 1
	}
	ext := s.segmentExt()
	for i := from; i < to; i++ {
		for v := 0; v < variants; v++ {
			path := filepath.Join(s.TmpDir, fmt.Sprintf("stream_%d_%03d%s", v, i, ext))
			if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
				log.Printf("Session %s: cannot purge %s: %v", s.ID, filepath.Base(path), err)
			}
		}
	}
	s.mu.Lock()
	if to > s.purgedBelow {
		s.purgedBelow = to
	}
	s.mu.Unlock()
}

// segmentExt is the extension this session's segments carry, defaulting to
// MPEG-TS for a session created before the field existed.
func (s *TranscodeSession) segmentExt() string {
	if s.SegmentExt == "" {
		return ".ts"
	}
	return s.SegmentExt
}

func (s *TranscodeSession) signal(sig syscall.Signal) {
	// Pas de commande : une session que les tests posent dans le gestionnaire
	// sans lancer FFmpeg.
	if s.cmd != nil && s.cmd.Process != nil {
		_ = s.cmd.Process.Signal(sig)
	}
}

// Kill terminates FFmpeg (continuing it first if paused) and removes temp files.
func (s *TranscodeSession) Kill() {
	if health := s.Health(time.Now()); health.Speed > 0 && s.countVideoSegments() >= reportMinSegments {
		// Sous 1, c'est le serveur qui faisait attendre le lecteur, pas la ligne.
		log.Printf("Session %s: %s encodé à %.1f× la vitesse de lecture", s.ID, s.Quality, health.Speed)
	}
	s.mu.Lock()
	s.releaseBudgetLocked()
	if !s.active {
		s.mu.Unlock()
		s.logCPUCost()
		s.reportEnd()
		s.cleanup()
		return
	}
	s.mu.Unlock()

	s.cancel()

	if s.cmd.Process != nil {
		// A stopped process ignores SIGTERM, so resume it first.
		_ = s.cmd.Process.Signal(syscall.SIGCONT)
		_ = s.cmd.Process.Signal(syscall.SIGTERM)

		done := make(chan struct{})
		go func() {
			defer safego.Recover("streaming/session.go:288")
			for s.IsActive() {
				time.Sleep(20 * time.Millisecond)
			}
			close(done)
		}()

		select {
		case <-done:
		case <-time.After(3 * time.Second):
			_ = s.cmd.Process.Kill()
		}
	}

	s.mu.Lock()
	s.active = false
	s.mu.Unlock()

	// Après l'attente de FFmpeg, qui seule donne son temps processeur, et avant
	// le nettoyage, qui emporte les segments que le coût rapporte.
	s.logCPUCost()
	s.reportEnd()
	s.cleanup()
}

func (s *TranscodeSession) cleanup() {
	if s.TmpDir == "" {
		return
	}
	if err := os.RemoveAll(s.TmpDir); err != nil {
		log.Printf("Session %s: failed to remove temp dir %s: %v", s.ID, s.TmpDir, err)
	} else {
		log.Printf("Session %s: cleaned up temp dir %s", s.ID, s.TmpDir)
	}
}

// WaitForFile polls for a file (relative to TmpDir) to appear, failing fast if
// FFmpeg dies first.
func (s *TranscodeSession) WaitForFile(name string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	path := s.TmpDir + "/" + name

	for time.Now().Before(deadline) {
		if _, err := os.Stat(path); err == nil {
			return nil
		}
		if !s.IsActive() {
			if errStr := s.stderr.String(); errStr != "" {
				log.Printf("Session %s: ffmpeg stderr: %s", s.ID, errStr)
			}
			return errFFmpegDied
		}
		time.Sleep(50 * time.Millisecond)
	}

	// Running out of budget is not a failure for the caller that matters here:
	// /start probes briefly and expects to time out on a healthy session. Anything
	// FFmpeg found worth printing in that window still is worth seeing.
	if errStr := s.stderr.String(); errStr != "" {
		log.Printf("Session %s: ffmpeg stderr while waiting for %s: %s", s.ID, name, errStr)
	}
	return errWaitTimeout
}
