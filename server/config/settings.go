package config

import (
	"database/sql"
	"errors"
	"log"
	"os"
	"strings"
	"sync"

	"project-player/server/database"
	"project-player/server/mediahub"
	"project-player/server/otp"
)

const (
	KeyMediaHubURL          = "mediahub_url"
	KeyMediaHubAPIKey       = "mediahub_api_key"
	KeyRequestService       = "request_service"
	KeyTMDBAPIKey           = "tmdb_api_key"
	KeyTMDBLanguage         = "tmdb_language"
	KeyFanartAPIKey         = "fanart_api_key"
	KeyPlaybackLogsEnabled  = "playback_logs_enabled"
	KeyPlaybackStatsEnabled = "playback_stats_enabled"
	KeyOTPPolicy            = "otp_policy"
	// KeySetupCompleted : l'assistant du premier lancement est terminé ou
	// écarté (ADR-0164). Absent, l'assistant reste proposé à l'administrateur.
	KeySetupCompleted = "setup_completed"
)

var (
	mu    sync.RWMutex
	cache map[string]string
)

func init() {
	cache = make(map[string]string)
}

// LoadCache reads all settings from SQLite into memory. Call after InitDB.
func LoadCache() {
	if database.DB == nil {
		return
	}
	rows, err := database.DB.Query(`SELECT key, value FROM app_settings`)
	if err != nil {
		log.Printf("config: failed to load settings: %v", err)
		return
	}
	defer rows.Close()

	next := make(map[string]string)
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			continue
		}
		next[k] = v
	}
	mu.Lock()
	cache = next
	mu.Unlock()
	log.Printf("config: loaded %d setting(s) from database", len(next))
}

func getStored(key string) (string, bool) {
	mu.RLock()
	defer mu.RUnlock()
	v, ok := cache[key]
	if !ok {
		return "", false
	}
	v = strings.TrimSpace(v)
	if v == "" {
		return "", false
	}
	return v, true
}

func setStored(key, value string) error {
	value = strings.TrimSpace(value)
	if database.DB == nil {
		return sql.ErrConnDone
	}
	if value == "" {
		_, err := database.DB.Exec(`DELETE FROM app_settings WHERE key = ?`, key)
		if err != nil {
			return err
		}
		mu.Lock()
		delete(cache, key)
		mu.Unlock()
		return nil
	}
	_, err := database.DB.Exec(`
		INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = CURRENT_TIMESTAMP
	`, key, value)
	if err != nil {
		return err
	}
	mu.Lock()
	cache[key] = value
	mu.Unlock()
	return nil
}

// MediaHubURL returns persisted URL, then MEDIAHUB_URL env.
func MediaHubURL() string {
	if v, ok := getStored(KeyMediaHubURL); ok {
		return strings.TrimRight(v, "/")
	}
	return strings.TrimRight(strings.TrimSpace(os.Getenv("MEDIAHUB_URL")), "/")
}

// MediaHubAPIKey returns persisted key, then MEDIAHUB_API_KEY env.
func MediaHubAPIKey() string {
	if v, ok := getStored(KeyMediaHubAPIKey); ok {
		return v
	}
	return strings.TrimSpace(os.Getenv("MEDIAHUB_API_KEY"))
}

// RequestService dit quel compagnon de demandes est à l'adresse réglée
// (ADR-0136) : réglage, puis REQUEST_SERVICE, sinon MediaHub. mediahub_url et
// mediahub_api_key gardent leur nom d'avant le choix du service, que MediaHub
// et les apps déjà installées écrivent encore.
func RequestService() mediahub.Service {
	if v, ok := getStored(KeyRequestService); ok {
		if service, valid := mediahub.ParseService(v); valid {
			return service
		}
	}
	service, _ := mediahub.ParseService(os.Getenv("REQUEST_SERVICE"))
	return service
}

func isPlaceholderTMDBKey(key string) bool {
	return key == "" ||
		key == "your_tmdb_api_key_here" ||
		key == "votre_cle_api_tmdb_ici"
}

// TMDBAPIKey returns a usable TMDB key (db → env), or empty if unset/placeholder.
func TMDBAPIKey() string {
	if v, ok := getStored(KeyTMDBAPIKey); ok && !isPlaceholderTMDBKey(v) {
		return v
	}
	key := strings.TrimSpace(os.Getenv("TMDB_API_KEY"))
	if isPlaceholderTMDBKey(key) {
		return ""
	}
	return key
}

// TMDBLanguage returns persisted language, then TMDB_LANGUAGE, then fr-FR.
func TMDBLanguage() string {
	if v, ok := getStored(KeyTMDBLanguage); ok {
		return v
	}
	lang := strings.TrimSpace(os.Getenv("TMDB_LANGUAGE"))
	if lang == "" {
		return "fr-FR"
	}
	return lang
}

// FanartAPIKey returns persisted key, then FANART_API_KEY env. Facultative :
// sans elle, le choix d'affiche ne propose que celles de TMDB.
func FanartAPIKey() string {
	if v, ok := getStored(KeyFanartAPIKey); ok {
		return v
	}
	return strings.TrimSpace(os.Getenv("FANART_API_KEY"))
}

// PlaybackLogsEnabled returns whether playback logs are enabled (db → env → true).
func PlaybackLogsEnabled() bool {
	if v, ok := getStored(KeyPlaybackLogsEnabled); ok {
		return v == "true" || v == "1" || v == "yes"
	}
	env := strings.TrimSpace(os.Getenv("PLAYBACK_LOGS_ENABLED"))
	if env != "" {
		return env == "true" || env == "1" || env == "yes"
	}
	return true
}

// PlaybackStatsEnabled returns whether plays attach their measurements
// (db → env → true).
//
// Séparé des journaux parce que les deux ne coûtent pas la même chose : le
// journal ne pèse que sur la fin d'une lecture, alors que les mesures
// interrogent le moteur toutes les cinq secondes pendant toute la séance. Sur
// un téléviseur d'entrée de gamme, c'est une raison suffisante de vouloir l'un
// sans l'autre.
func PlaybackStatsEnabled() bool {
	if v, ok := getStored(KeyPlaybackStatsEnabled); ok {
		return v == "true" || v == "1" || v == "yes"
	}
	env := strings.TrimSpace(os.Getenv("PLAYBACK_STATS_ENABLED"))
	if env != "" {
		return env == "true" || env == "1" || env == "yes"
	}
	return true
}

// OTPPolicy est la politique de validation en deux étapes du serveur
// (db → OTP_POLICY → facultative). Une valeur inconnue retombe sur la
// politique par défaut plutôt que de fermer ou d'ouvrir la porte au hasard.
func OTPPolicy() otp.Policy {
	if v, ok := getStored(KeyOTPPolicy); ok {
		if p, valid := otp.ParsePolicy(v); valid {
			return p
		}
	}
	if p, valid := otp.ParsePolicy(strings.TrimSpace(os.Getenv("OTP_POLICY"))); valid {
		return p
	}
	return otp.DefaultPolicy
}

// SetupCompleted dit si l'assistant du premier lancement est terminé. Seule
// partie de l'état de l'installation qui est un drapeau : le reste se calcule
// depuis les données (handlers/setup.go).
func SetupCompleted() bool {
	v, ok := getStored(KeySetupCompleted)
	return ok && v == "true"
}

// MarkSetupCompleted pose le drapeau. Il ne se retire pas : un assistant
// terminé ne se rouvre pas de lui-même.
func MarkSetupCompleted() error {
	return setStored(KeySetupCompleted, "true")
}

// PublicSettings is the safe API payload (secrets never returned in clear).
type PublicSettings struct {
	MediaHubURL        string `json:"mediahub_url"`
	MediaHubAPIKeySet  bool   `json:"mediahub_api_key_set"`
	MediaHubAPIKeyHint string `json:"mediahub_api_key_hint,omitempty"`
	// RequestService : "mediahub", "overseerr" ou "jellyseerr" (ADR-0136).
	RequestService       string `json:"request_service"`
	TMDBAPIKeySet        bool   `json:"tmdb_api_key_set"`
	TMDBAPIKeyHint       string `json:"tmdb_api_key_hint,omitempty"`
	TMDBLanguage         string `json:"tmdb_language"`
	FanartAPIKeySet      bool   `json:"fanart_api_key_set"`
	FanartAPIKeyHint     string `json:"fanart_api_key_hint,omitempty"`
	PlaybackLogsEnabled  bool   `json:"playback_logs_enabled"`
	PlaybackStatsEnabled bool   `json:"playback_stats_enabled"`
	OTPPolicy            string `json:"otp_policy"`
}

func maskSecret(secret string) string {
	secret = strings.TrimSpace(secret)
	if secret == "" {
		return ""
	}
	if len(secret) <= 4 {
		return "••••"
	}
	return "••••" + secret[len(secret)-4:]
}

// Snapshot returns public settings for GET /api/settings.
func Snapshot() PublicSettings {
	mhKey := MediaHubAPIKey()
	tmdbKey := TMDBAPIKey()
	fanartKey := FanartAPIKey()
	return PublicSettings{
		MediaHubURL:          MediaHubURL(),
		MediaHubAPIKeySet:    mhKey != "",
		MediaHubAPIKeyHint:   maskSecret(mhKey),
		RequestService:       string(RequestService()),
		TMDBAPIKeySet:        tmdbKey != "",
		TMDBAPIKeyHint:       maskSecret(tmdbKey),
		TMDBLanguage:         TMDBLanguage(),
		FanartAPIKeySet:      fanartKey != "",
		FanartAPIKeyHint:     maskSecret(fanartKey),
		PlaybackLogsEnabled:  PlaybackLogsEnabled(),
		PlaybackStatsEnabled: PlaybackStatsEnabled(),
		OTPPolicy:            string(OTPPolicy()),
	}
}

// UpdateRequest is the PUT /api/settings body. Omitted/blank secrets keep current values.
type UpdateRequest struct {
	MediaHubURL         *string `json:"mediahub_url"`
	MediaHubAPIKey      *string `json:"mediahub_api_key"`
	ClearMediaHubAPIKey bool    `json:"clear_mediahub_api_key"`
	// RequestService : une des valeurs de mediahub.Service. Une autre est
	// refusée avant toute écriture.
	RequestService       *string `json:"request_service"`
	TMDBAPIKey           *string `json:"tmdb_api_key"`
	ClearTMDBAPIKey      bool    `json:"clear_tmdb_api_key"`
	TMDBLanguage         *string `json:"tmdb_language"`
	FanartAPIKey         *string `json:"fanart_api_key"`
	ClearFanartAPIKey    bool    `json:"clear_fanart_api_key"`
	PlaybackLogsEnabled  *bool   `json:"playback_logs_enabled"`
	PlaybackStatsEnabled *bool   `json:"playback_stats_enabled"`
	// OTPPolicy : une des valeurs d'otp.Policy. Le handler refuse les autres
	// avant d'arriver ici.
	OTPPolicy *string `json:"otp_policy"`
}

// ApplyUpdate persists partial updates and returns the new public snapshot.
func ApplyUpdate(req UpdateRequest) (PublicSettings, error) {
	// Refusée avant toute écriture : une requête invalide ne laisse pas la
	// moitié de ses réglages enregistrés.
	var policy otp.Policy
	if req.OTPPolicy != nil {
		var ok bool
		if policy, ok = otp.ParsePolicy(*req.OTPPolicy); !ok {
			return PublicSettings{}, ErrInvalidOTPPolicy
		}
	}

	var service mediahub.Service
	if req.RequestService != nil {
		var ok bool
		if service, ok = mediahub.ParseService(*req.RequestService); !ok {
			return PublicSettings{}, ErrInvalidRequestService
		}
	}

	if req.RequestService != nil {
		if err := setStored(KeyRequestService, string(service)); err != nil {
			return PublicSettings{}, err
		}
	}
	if req.MediaHubURL != nil {
		if err := setStored(KeyMediaHubURL, strings.TrimRight(strings.TrimSpace(*req.MediaHubURL), "/")); err != nil {
			return PublicSettings{}, err
		}
	}
	if req.ClearMediaHubAPIKey {
		if err := setStored(KeyMediaHubAPIKey, ""); err != nil {
			return PublicSettings{}, err
		}
	} else if req.MediaHubAPIKey != nil && strings.TrimSpace(*req.MediaHubAPIKey) != "" {
		if err := setStored(KeyMediaHubAPIKey, *req.MediaHubAPIKey); err != nil {
			return PublicSettings{}, err
		}
	}

	if req.ClearTMDBAPIKey {
		if err := setStored(KeyTMDBAPIKey, ""); err != nil {
			return PublicSettings{}, err
		}
	} else if req.TMDBAPIKey != nil && strings.TrimSpace(*req.TMDBAPIKey) != "" {
		if err := setStored(KeyTMDBAPIKey, *req.TMDBAPIKey); err != nil {
			return PublicSettings{}, err
		}
	}

	if req.TMDBLanguage != nil {
		lang := strings.TrimSpace(*req.TMDBLanguage)
		if lang == "" {
			lang = "fr-FR"
		}
		if err := setStored(KeyTMDBLanguage, lang); err != nil {
			return PublicSettings{}, err
		}
	}
	if req.ClearFanartAPIKey {
		if err := setStored(KeyFanartAPIKey, ""); err != nil {
			return PublicSettings{}, err
		}
	} else if req.FanartAPIKey != nil && strings.TrimSpace(*req.FanartAPIKey) != "" {
		if err := setStored(KeyFanartAPIKey, *req.FanartAPIKey); err != nil {
			return PublicSettings{}, err
		}
	}
	if req.PlaybackLogsEnabled != nil {
		value := "false"
		if *req.PlaybackLogsEnabled {
			value = "true"
		}
		if err := setStored(KeyPlaybackLogsEnabled, value); err != nil {
			return PublicSettings{}, err
		}
	}
	if req.PlaybackStatsEnabled != nil {
		value := "false"
		if *req.PlaybackStatsEnabled {
			value = "true"
		}
		if err := setStored(KeyPlaybackStatsEnabled, value); err != nil {
			return PublicSettings{}, err
		}
	}

	if req.OTPPolicy != nil {
		if err := setStored(KeyOTPPolicy, string(policy)); err != nil {
			return PublicSettings{}, err
		}
	}

	return Snapshot(), nil
}

// CheckRequestServiceNeedsTMDB refuse (ErrTMDBKeyRequired) une mise à jour qui
// met en place ou change le service de demandes sans qu'une clé TMDB existe
// une fois la mise à jour appliquée (ADR-0164) : le catalogue, les fiches et
// les épisodes des demandes viennent de TMDB pour les trois services, et un
// service enregistré sans elle ne montrerait que des écrans vides.
//
// À appeler avant ApplyUpdate, pour que le refus n'écrive rien. Seul le
// formulaire des réglages (PUT /api/settings) la pose : MediaHub, qui réécrit
// son adresse ou sa clé par la clé d'intégration, parle d'un service déjà
// en place et n'est jamais bloqué. Un service inconnu n'est pas son affaire :
// ApplyUpdate le refuse.
func CheckRequestServiceNeedsTMDB(req UpdateRequest) error {
	var service mediahub.Service
	if req.RequestService != nil {
		var ok bool
		if service, ok = mediahub.ParseService(*req.RequestService); !ok {
			return nil
		}
	}
	if configuresRequestService(req, service) && !tmdbKeyAvailableAfter(req) {
		return ErrTMDBKeyRequired
	}
	return nil
}

// configuresRequestService dit si req met en place ou change le service de
// demandes : un service, une adresse ou une clé différents de ceux en place.
// Rejouer les valeurs déjà enregistrées, ou en retirer, ne le configure pas :
// une configuration déjà en place n'est jamais bloquée après coup. service est
// celui de req.RequestService, déjà validé.
func configuresRequestService(req UpdateRequest, service mediahub.Service) bool {
	if req.RequestService != nil && service != RequestService() {
		return true
	}
	if req.MediaHubURL != nil {
		next := strings.TrimRight(strings.TrimSpace(*req.MediaHubURL), "/")
		if next != "" && next != MediaHubURL() {
			return true
		}
	}
	if !req.ClearMediaHubAPIKey && req.MediaHubAPIKey != nil {
		next := strings.TrimSpace(*req.MediaHubAPIKey)
		if next != "" && next != MediaHubAPIKey() {
			return true
		}
	}
	return false
}

// tmdbKeyAvailableAfter dit si une clé TMDB utilisable existera une fois req
// appliquée : celle que req enregistre, sinon celle en place (réglage ou
// environnement), et seulement l'environnement si req efface la clé.
func tmdbKeyAvailableAfter(req UpdateRequest) bool {
	if req.ClearTMDBAPIKey {
		return !isPlaceholderTMDBKey(strings.TrimSpace(os.Getenv("TMDB_API_KEY")))
	}
	if req.TMDBAPIKey != nil {
		if key := strings.TrimSpace(*req.TMDBAPIKey); key != "" {
			return !isPlaceholderTMDBKey(key) || TMDBAPIKey() != ""
		}
	}
	return TMDBAPIKey() != ""
}

// ErrTMDBKeyRequired : un service de demandes ne s'enregistre pas sans clé TMDB.
var ErrTMDBKeyRequired = errors.New("config: a TMDB key is required for the request service")

// ErrInvalidRequestService : le service de demandes demandé n'existe pas.
var ErrInvalidRequestService = errors.New("config: invalid request service")

// ErrInvalidOTPPolicy : la politique demandée n'existe pas.
var ErrInvalidOTPPolicy = errors.New("config: invalid otp policy")
