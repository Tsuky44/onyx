package mediahub

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"project-player/server/safego"
	"project-player/server/ttlcache"
)

// Ce que Seerr sait d'un titre : sa fiche (GET /movie/:id, GET /tv/:id) porte
// à la fois les textes de TMDB et, sous mediaInfo, l'état chez Seerr, ses
// demandes et ses téléchargements. Il n'a ni lot de disponibilités ni titre
// dans ses demandes : Onyx lit la fiche, et la retient un moment.

type seerrSeason struct {
	SeasonNumber int `json:"seasonNumber"`
	Status       int `json:"status"`
	Status4k     int `json:"status4k"`
}

// seerrDownload est un téléchargement en cours chez Radarr ou Sonarr, tel que
// Seerr le relève. Les tailles sont en octets, la durée en « hh:mm:ss ».
type seerrDownload struct {
	Title    string  `json:"title"`
	Size     float64 `json:"size"`
	SizeLeft float64 `json:"sizeLeft"`
	TimeLeft string  `json:"timeLeft"`
}

// seerrMedia est l'état d'un titre chez Seerr.
type seerrMedia struct {
	ID               int             `json:"id"`
	TMDBID           int             `json:"tmdbId"`
	Status           int             `json:"status"`
	Status4k         int             `json:"status4k"`
	Seasons          []seerrSeason   `json:"seasons"`
	Requests         []seerrRequest  `json:"requests"`
	DownloadStatus   []seerrDownload `json:"downloadStatus"`
	DownloadStatus4k []seerrDownload `json:"downloadStatus4k"`
}

// status rend l'état du titre dans la qualité demandée.
func (m *seerrMedia) status(is4k bool) int {
	if m == nil {
		return 0
	}
	if is4k {
		return m.Status4k
	}
	return m.Status
}

// seasonStatus rend l'état de la saison chez Seerr, ou 0 s'il ne la suit pas.
func (m *seerrMedia) seasonStatus(number int, is4k bool) int {
	if m == nil {
		return 0
	}
	for _, season := range m.Seasons {
		if season.SeasonNumber == number {
			if is4k {
				return season.Status4k
			}
			return season.Status
		}
	}
	return 0
}

func (m *seerrMedia) downloads(is4k bool) []seerrDownload {
	if m == nil {
		return nil
	}
	if is4k {
		return m.DownloadStatus4k
	}
	return m.DownloadStatus
}

// seerrDetails est la fiche d'un titre : title pour un film, name pour une
// série.
type seerrDetails struct {
	Title      string      `json:"title"`
	Name       string      `json:"name"`
	PosterPath *string     `json:"posterPath"`
	MediaInfo  *seerrMedia `json:"mediaInfo"`
	Seasons    []struct {
		SeasonNumber int `json:"seasonNumber"`
		EpisodeCount int `json:"episodeCount"`
	} `json:"seasons"`
}

// seerrTitle est ce qu'Onyx montre d'une demande et que Seerr ne garde pas.
type seerrTitle struct {
	Title      string
	PosterPath *string
}

// Une fiche se retient trente secondes : le temps d'une page du catalogue ou
// d'une liste de demandes, sans masquer longtemps une demande qui avance. Le
// titre et l'affiche, eux, ne changent pas : un jour.
var (
	seerrDetailsCache = newSeerrDetailsCache()
	seerrTitles       = newSeerrTitles()
)

func newSeerrDetailsCache() *ttlcache.Cache[seerrDetails] {
	return ttlcache.New[seerrDetails](30*time.Second, 500)
}

func newSeerrTitles() *ttlcache.Cache[seerrTitle] {
	return ttlcache.New[seerrTitle](24*time.Hour, 4000)
}

// seerrFanOut borne les fiches lues en même temps : Seerr va chercher chez
// TMDB celles qu'il n'a pas en mémoire.
const seerrFanOut = 6

func (c Client) seerrTitleKey(mediaType string, tmdbID int) string {
	return c.base() + "\n" + c.Language + "\n" + AvailabilityKey(mediaType, tmdbID)
}

func (c Client) forgetSeerrDetails(mediaType string, tmdbID int) {
	seerrDetailsCache.Delete(c.seerrTitleKey(mediaType, tmdbID))
}

// seerrDetails lit la fiche d'un titre. fresh passe outre la mémoire : le
// suivi d'un téléchargement ne vaut que frais.
func (c Client) seerrDetails(ctx context.Context, mediaType string, tmdbID int, fresh bool) (seerrDetails, error) {
	key := c.seerrTitleKey(mediaType, tmdbID)
	if !fresh {
		if details, ok := seerrDetailsCache.Get(key); ok {
			return details, nil
		}
	}
	path := "/movie/" + strconv.Itoa(tmdbID)
	if mediaType == "tv" {
		path = "/tv/" + strconv.Itoa(tmdbID)
	}
	query := url.Values{}
	if c.Language != "" {
		query.Set("language", c.Language)
	}
	raw, err := c.seerr(ctx, http.MethodGet, path, 0, query, nil)
	if err != nil {
		return seerrDetails{}, err
	}
	var details seerrDetails
	if err := json.Unmarshal(raw, &details); err != nil {
		return seerrDetails{}, fmt.Errorf("mediahub: decode seerr details: %w", err)
	}
	seerrDetailsCache.Put(key, details)
	title := details.Title
	if title == "" {
		title = details.Name
	}
	if title != "" {
		seerrTitles.Put(key, seerrTitle{Title: title, PosterPath: details.PosterPath})
	}
	return details, nil
}

// seerrMediaStatus traduit l'état d'un titre. Ce que Jellyseerr range après
// « disponible » (bloqué, supprimé) n'est suivi par personne : inconnu.
func seerrMediaStatus(status int) string {
	switch status {
	case seerrMediaPending:
		return "pending"
	case seerrMediaProcessing:
		return "processing"
	case seerrMediaPartial:
		return "partial"
	case seerrMediaAvailable:
		return "available"
	default:
		return "unknown"
	}
}

// seerrSeasonStatus dit où en est une saison : ce que Seerr en détient
// d'abord, sinon la demande qui la couvre. Une demande refusée ne suit rien.
func seerrSeasonStatus(info *seerrMedia, number int) string {
	held := info.seasonStatus(number, false)
	if held == seerrMediaAvailable || held == seerrMediaPartial {
		return seerrMediaStatus(held)
	}
	for _, request := range info.Requests {
		if request.Is4k || request.Status == seerrRequestDeclined {
			continue
		}
		for _, season := range request.Seasons {
			if season.SeasonNumber != number {
				continue
			}
			if request.Status == seerrRequestPending {
				return "pending"
			}
			return "processing"
		}
	}
	if held == seerrMediaProcessing || held == seerrMediaPending {
		return seerrMediaStatus(held)
	}
	return "unknown"
}

// seerrAvailability rend la disponibilité d'un titre d'après sa fiche. Un
// titre que TMDB ne connaît pas (404) n'est pas une panne : inconnu.
func (c Client) seerrAvailability(ctx context.Context, tmdbID int, mediaType string) (*Availability, error) {
	availability := &Availability{Status: "unknown", Seasons: []SeasonAvailability{}}
	details, err := c.seerrDetails(ctx, mediaType, tmdbID, false)
	var refused *StatusError
	if errors.As(err, &refused) && refused.Status == http.StatusNotFound {
		return availability, nil
	}
	if err != nil {
		return nil, err
	}
	info := details.MediaInfo
	if info == nil {
		// Seerr ne suit pas le titre : chaque saison reste à demander.
		info = &seerrMedia{}
	}
	availability.Status = seerrMediaStatus(info.Status)
	if mediaType != "tv" {
		return availability, nil
	}
	for _, season := range details.Seasons {
		availability.Seasons = append(availability.Seasons, SeasonAvailability{
			SeasonNumber:  season.SeasonNumber,
			Status:        seerrSeasonStatus(info, season.SeasonNumber),
			TotalEpisodes: season.EpisodeCount,
		})
	}
	return availability, nil
}

// seerrAvailabilityBatch lit les fiches de la page, quelques-unes à la fois.
// Une fiche qui échoue laisse sa carte sans pastille, comme avec MediaHub.
func (c Client) seerrAvailabilityBatch(ctx context.Context, items []BatchItem) (map[string]string, error) {
	if !c.Configured() {
		return nil, ErrNotConfigured
	}
	if len(items) > MaxBatch {
		items = items[:MaxBatch]
	}
	var (
		mu       sync.Mutex
		wg       sync.WaitGroup
		statuses = make(map[string]string, len(items))
		muted    error
		slots    = make(chan struct{}, seerrFanOut)
	)
	for _, item := range items {
		wg.Add(1)
		go func(item BatchItem) {
			defer safego.Recover("mediahub/seerr_media.go: availability batch")
			defer wg.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			availability, err := c.seerrAvailability(ctx, item.TMDBID, item.MediaType)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				if IsUnreachable(err) {
					muted = err
				}
				return
			}
			statuses[AvailabilityKey(item.MediaType, item.TMDBID)] = availability.Status
		}(item)
	}
	wg.Wait()
	// Rien n'a répondu : c'est l'adresse, pas un titre.
	if len(statuses) == 0 && muted != nil {
		return nil, muted
	}
	return statuses, nil
}

// seerrProgress rend le téléchargement en cours du titre. Seerr ne suit pas
// l'import : Imports reste vide.
func (c Client) seerrProgress(ctx context.Context, tmdbID int, mediaType string) (Progress, error) {
	progress := Progress{Imports: []Import{}}
	details, err := c.seerrDetails(ctx, mediaType, tmdbID, true)
	if err != nil {
		return Progress{}, err
	}
	downloads := details.MediaInfo.downloads(false)
	if len(downloads) == 0 {
		return progress, nil
	}
	var size, left float64
	for _, download := range downloads {
		size += download.Size
		left += download.SizeLeft
	}
	download := Download{}
	if percent := seerrDownloadPercent(downloads); percent != nil {
		download.Progress = *percent
	}
	if size > 0 {
		sizeText, leftText := seerrBytes(size), seerrBytes(left)
		download.Size, download.SizeLeft = &sizeText, &leftText
	}
	if timeLeft := seerrTimeLeft(downloads[0].TimeLeft); timeLeft != "" {
		download.TimeLeft = &timeLeft
	}
	if title := strings.TrimSpace(downloads[0].Title); title != "" {
		download.ReleaseTitle = &title
	}
	progress.Active, progress.Downloading, progress.Download = true, true, &download
	return progress, nil
}

// seerrDownloadPercent rend l'avancement des téléchargements, de 0 à 100, ou
// nil quand rien ne se télécharge ou que les tailles ne sont pas connues.
func seerrDownloadPercent(downloads []seerrDownload) *float64 {
	var size, left float64
	for _, download := range downloads {
		size += download.Size
		left += download.SizeLeft
	}
	if size <= 0 {
		return nil
	}
	percent := (size - left) / size * 100
	if percent < 0 {
		percent = 0
	}
	if percent > 100 {
		percent = 100
	}
	return &percent
}

// seerrBytes écrit une taille comme MediaHub les envoie (« 1.2 GB »).
func seerrBytes(bytes float64) string {
	units := []string{"B", "KB", "MB", "GB", "TB"}
	unit := 0
	for bytes >= 1024 && unit < len(units)-1 {
		bytes /= 1024
		unit++
	}
	if unit == 0 {
		return fmt.Sprintf("%.0f %s", bytes, units[unit])
	}
	return fmt.Sprintf("%.1f %s", bytes, units[unit])
}

// seerrTimeLeft raccourcit « 01:05:09 » (ou « 1.02:03:04 », avec des jours) en
// « 1h05 », « 12m » : la forme courte de MediaHub. Une durée illisible passe
// telle quelle.
func seerrTimeLeft(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	days := 0
	clock := raw
	if dot := strings.Index(raw, "."); dot >= 0 && strings.Count(raw[dot:], ":") == 2 {
		value, err := strconv.Atoi(raw[:dot])
		if err != nil {
			return raw
		}
		days, clock = value, raw[dot+1:]
	}
	parts := strings.Split(clock, ":")
	if len(parts) != 3 {
		return raw
	}
	hours, errH := strconv.Atoi(parts[0])
	minutes, errM := strconv.Atoi(parts[1])
	if errH != nil || errM != nil {
		return raw
	}
	hours += days * 24
	switch {
	case hours > 0:
		return fmt.Sprintf("%dh%02d", hours, minutes)
	case minutes > 0:
		return fmt.Sprintf("%dm", minutes)
	default:
		return "<1m"
	}
}

// seerrForget retire un titre entier de Seerr avant qu'Onyx n'efface ce qui
// reste sur le disque (ADR-0128) : de Radarr ou Sonarr avec ses fichiers, puis
// la fiche et ses demandes, pour que le titre redevienne demandable. Seerr ne
// sait pas retirer une seule saison : rien n'y bouge, et Sonarr la suit encore.
func (c Client) seerrForget(ctx context.Context, as Account, tmdbID int, mediaType string, season *int) (Removal, error) {
	removal := Removal{Manager: "arr"}
	if season != nil {
		return removal, nil
	}
	identity, err := c.seerrIdentity(ctx, as)
	if err != nil {
		return Removal{}, err
	}
	details, err := c.seerrDetails(ctx, mediaType, tmdbID, true)
	var refused *StatusError
	if errors.As(err, &refused) && refused.Status == http.StatusNotFound {
		return removal, nil
	}
	if err != nil {
		return Removal{}, err
	}
	info := details.MediaInfo
	if info == nil || info.ID <= 0 {
		// Seerr ne suit pas le titre : ni gestionnaire ni demandes à prévenir.
		return removal, nil
	}
	media := "/media/" + strconv.Itoa(info.ID)

	// Seerr répond 404 quand Radarr ou Sonarr n'a pas le titre comme quand
	// la route n'existe pas (un Overseerr ancien) : dans les deux cas il n'y
	// a rien à retirer de plus, et la fiche part quand même.
	_, err = c.seerr(ctx, http.MethodDelete, media+"/file", identity.user.ID, nil, nil)
	switch {
	case err == nil:
		removal.ManagerRemoved = true
	case errors.As(err, &refused) && refused.Status == http.StatusForbidden:
		return Removal{}, err
	case !errors.As(err, &refused):
		return Removal{}, err
	}

	if _, err := c.seerr(ctx, http.MethodDelete, media, identity.user.ID, nil, nil); err != nil {
		return Removal{}, err
	}
	removal.RequestsRemoved = len(info.Requests)
	c.forgetSeerrDetails(mediaType, tmdbID)
	return removal, nil
}
