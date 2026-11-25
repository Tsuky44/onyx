package streaming

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
)

// La réponse de /start, et celle de son refus.
//
// Extrait de handler.go, qui approche la limite de 800 lignes (ADR-0052).
// StartResponse est exportée pour le contrat d'API (handlers/contract_test.go,
// ADR-0051) : l'app la lit par HlsSession.fromJson.

// StartResponse is the JSON body returned when a session is created. The client
// opens MasterURL directly with media_kit (mpv resolves child playlists/segments
// relative to it; the server propagates its ticket into every playlist).
type StartResponse struct {
	SessionID   string  `json:"session_id"`
	MasterURL   string  `json:"master_url"`
	Duration    float64 `json:"duration"`
	StartOffset int     `json:"start_offset"`
	// Quality est le barreau servi. En Auto (auto=1), il peut être plus bas
	// que celui demandé : RequestedQuality dit alors lequel l'était.
	Quality string `json:"quality"`
	// RequestedQuality est le barreau demandé, présent seulement quand il
	// diffère de Quality (CapacityDegraded).
	RequestedQuality string `json:"requested_quality,omitempty"`
	// CapacityWarning dit que le serveur ne prévoit pas de tenir ce barreau
	// avec la marge voulue : CapacityDegraded (l'Auto a été descendu) ou
	// CapacityTooHeavy (servi tel quel, peut saccader). Absent sinon, et
	// toujours absent d'un serveur d'avant le budget (admission.go).
	CapacityWarning string `json:"capacity_warning,omitempty"`
	// AudioMap lists the source audio tracks published as renditions, in the
	// order the player will enumerate them. Position k in the player's audio
	// track list is source track AudioMap[k], which is how the client switches
	// language without asking for a new session.
	AudioMap []int `json:"audio_map"`
	// BurnedSubtitle echoes the bitmap subtitle stream rendered into the video,
	// or -1. The client compares it with what it asked for to know whether the
	// request was honoured.
	BurnedSubtitle int `json:"burned_subtitle"`
	// VideoMode is "copy" when the picture is being repackaged untouched and
	// "encode" when it is being re-encoded. VideoReason names why a copy was
	// refused, and is empty on the copy path.
	//
	// Both are for the viewer as much as for the log: "Direct Stream" and "why
	// is my CPU at 400%" are the same question, and answering it needs the
	// server's own reason rather than a guess reconstructed on the client.
	VideoMode   string `json:"video_mode"`
	VideoReason string `json:"video_reason,omitempty"`
	// Container is the segment format the session actually publishes.
	Container string `json:"container"`
	// RetainSeconds est ce que la session garde derrière le dernier segment
	// demandé, quand le client a dit savoir rouvrir une session pour reculer
	// plus loin (purge=1). Absent : tout est gardé.
	RetainSeconds int `json:"retain_seconds,omitempty"`
	// Subtitles are the text tracks this session writes as WebVTT, each with
	// the URL it grows at. Absent from a server that predates ADR-0031, which
	// the client takes as "fetch them the old way".
	Subtitles []liveSubtitle `json:"subtitles"`
	// Standby confirme que la session attend son lecteur sans rien remplacer
	// (`standby=1`). Absent d'un serveur qui ne connaît pas l'attente : la
	// session en cours y est déjà condamnée, et le client ne peut plus renoncer.
	Standby bool `json:"standby,omitempty"`
}

// startReply est ce que /start sait d'une session admise, pour la décrire.
type startReply struct {
	session      *TranscodeSession
	decision     admission
	video        VideoPlan
	caps         Capabilities
	audioMap     []int
	burnSubtitle int
	subtitles    []int
	retain       int
	standby      bool
}

// response est le corps de /start. Les URL portent le ticket de la requête :
// le lecteur les ouvre telles quelles.
func (rep startReply) response(r *http.Request) StartResponse {
	s := rep.session
	sessionURL := fmt.Sprintf("%s/api/v1/stream/%d/%s", BaseURL(r), s.MediaID, s.ID)
	ticketQuery := "?ticket=" + r.URL.Query().Get("ticket")
	subtitles := make([]liveSubtitle, 0, len(rep.subtitles))
	for _, typedIndex := range rep.subtitles {
		subtitles = append(subtitles, liveSubtitle{
			TypedIndex: typedIndex,
			URL:        sessionURL + "/" + LiveSubtitleFileName(typedIndex) + ticketQuery,
		})
	}
	// Le barreau demandé n'est renvoyé que s'il n'a pas été servi.
	requestedQuality := ""
	if rep.decision.requested != s.Quality {
		requestedQuality = rep.decision.requested
	}
	videoMode := "encode"
	if rep.video.Copy {
		videoMode = "copy"
	}
	duration := 0.0
	if s.Probe != nil {
		duration = s.Probe.Duration
	}
	return StartResponse{
		SessionID:        s.ID,
		MasterURL:        sessionURL + "/master.m3u8" + ticketQuery,
		Duration:         duration,
		StartOffset:      s.StartOffset,
		Quality:          s.Quality,
		RequestedQuality: requestedQuality,
		CapacityWarning:  rep.decision.warning,
		AudioMap:         rep.audioMap,
		BurnedSubtitle:   rep.burnSubtitle,
		VideoMode:        videoMode,
		VideoReason:      rep.video.Reason,
		Container:        string(rep.caps.Container),
		RetainSeconds:    rep.retain,
		Subtitles:        subtitles,
		Standby:          rep.standby,
	}
}

// liveSubtitle is one text track a session writes, as /start announces it.
type liveSubtitle struct {
	TypedIndex int    `json:"typed_index"`
	URL        string `json:"url"`
}

// busyResponse est le corps du 503 server_busy : un code stable pour l'app, et
// une raison lisible pour qui lit la réponse ou le journal.
type busyResponse struct {
	Error  string `json:"error"`
	Reason string `json:"reason"`
}

// writeServerBusy répond 503 server_busy : la limite dure est atteinte, et le
// client peut réessayer dans retryAfter secondes.
func writeServerBusy(w http.ResponseWriter, retryAfter int, reason string) {
	w.Header().Set("Retry-After", strconv.Itoa(retryAfter))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusServiceUnavailable)
	_ = json.NewEncoder(w).Encode(busyResponse{Error: "server_busy", Reason: reason})
}
