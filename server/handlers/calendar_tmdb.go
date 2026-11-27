package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"project-player/server/calendar"
	"project-player/server/httpx"
	"project-player/server/safego"
	"project-player/server/tmdb"
	"project-player/server/ttlcache"
)

// Les programmes TMDB du calendrier « À venir » (ADR
// 2026-11-27-tsuky-calendrier-sorties-serveur). Une date d'épisode bouge
// rarement d'une heure à l'autre : trois heures de cache font qu'un compte
// qui rouvre l'onglet ne relance aucun appel, et qu'un second compte qui
// regarde la même série profite du premier.
const (
	calendarShowCacheTTL  = 3 * time.Hour
	calendarMovieCacheTTL = 6 * time.Hour
	// calendarCacheMax : un programme par série ou film suivi par au moins un
	// compte, plus les séries récentes de la bibliothèque, par langue.
	calendarCacheMax = 2048
	// calendarFetchParallel borne les appels TMDB simultanés d'un même
	// calendrier : TMDB limite le débit, et httpx réessaie déjà sur 429.
	calendarFetchParallel = 6
	// calendarSeasonsMax : la saison en cours, la précédente si elle vient de
	// finir, la suivante si elle est datée. Au-delà, rien ne tombe dans la
	// fenêtre du calendrier.
	calendarSeasonsMax = 3
)

var (
	calendarShowCache  = ttlcache.New[calendar.Show](calendarShowCacheTTL, calendarCacheMax)
	calendarMovieCache = ttlcache.New[calendar.Movie](calendarMovieCacheTTL, calendarCacheMax)
)

// calendarSchedules rend les programmes connus des intérêts, en attendant au
// plus budget. Ce qui arrive après continue de remplir le cache : le
// prochain chargement l'aura, et ce calendrier-ci n'attend pas une série
// lente pour montrer les autres.
func calendarSchedules(interests []calendar.Interest, lang mediaLanguage, today time.Time, budget time.Duration) (map[int]calendar.Show, map[int]calendar.Movie) {
	shows := map[int]calendar.Show{}
	movies := map[int]calendar.Movie{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	slots := make(chan struct{}, calendarFetchParallel)

	for _, it := range interests {
		it := it
		switch it.Kind {
		case calendar.KindShow:
			if cached, ok := calendarShowCache.Get(calendarCacheKey(it.TMDBID, lang)); ok {
				shows[it.TMDBID] = cached
				continue
			}
		case calendar.KindMovie:
			if cached, ok := calendarMovieCache.Get(calendarCacheKey(it.TMDBID, lang)); ok {
				movies[it.TMDBID] = cached
				continue
			}
		default:
			continue
		}
		wg.Add(1)
		go safego.Run("calendar schedule", func() {
			defer wg.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			switch it.Kind {
			case calendar.KindShow:
				if show, ok := fetchCalendarShow(it.TMDBID, lang, today); ok {
					mu.Lock()
					shows[it.TMDBID] = show
					mu.Unlock()
				}
			case calendar.KindMovie:
				if movie, ok := fetchCalendarMovie(it.TMDBID, lang); ok {
					mu.Lock()
					movies[it.TMDBID] = movie
					mu.Unlock()
				}
			}
		})
	}

	done := make(chan struct{})
	go safego.Run("calendar schedule wait", func() {
		wg.Wait()
		close(done)
	})
	select {
	case <-done:
	case <-time.After(budget):
	}

	mu.Lock()
	defer mu.Unlock()
	outShows := make(map[int]calendar.Show, len(shows))
	for id, s := range shows {
		outShows[id] = s
	}
	outMovies := make(map[int]calendar.Movie, len(movies))
	for id, m := range movies {
		outMovies[id] = m
	}
	return outShows, outMovies
}

func calendarCacheKey(tmdbID int, lang mediaLanguage) string {
	return strconv.Itoa(tmdbID) + "/" + lang.code
}

// fetchCalendarShow lit le programme d'une série : sa fiche TMDB, puis les
// épisodes des saisons qui peuvent tomber dans le calendrier. Un échec n'est
// pas mis en cache, pour qu'une panne passagère de TMDB ne vide pas la série
// pendant trois heures.
func fetchCalendarShow(tmdbID int, lang mediaLanguage, today time.Time) (calendar.Show, bool) {
	if tmdbID <= 0 || tmdbRequestAPIKey() == "" {
		return calendar.Show{}, false
	}
	resp, err := tmdb.Get(httpx.Standard, fmt.Sprintf("/tv/%d?language=%s", tmdbID, lang.tmdbLocale()))
	if err != nil {
		return calendar.Show{}, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return calendar.Show{}, false
	}
	type episodeRef struct {
		SeasonNumber int `json:"season_number"`
	}
	var payload struct {
		Name             string      `json:"name"`
		PosterPath       *string     `json:"poster_path"`
		NextEpisodeToAir *episodeRef `json:"next_episode_to_air"`
		LastEpisodeToAir *episodeRef `json:"last_episode_to_air"`
		Seasons          []struct {
			SeasonNumber int    `json:"season_number"`
			AirDate      string `json:"air_date"`
		} `json:"seasons"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return calendar.Show{}, false
	}

	var seasons []int
	add := func(n int) {
		if n <= 0 || len(seasons) >= calendarSeasonsMax {
			return
		}
		for _, s := range seasons {
			if s == n {
				return
			}
		}
		seasons = append(seasons, n)
	}
	if payload.NextEpisodeToAir != nil {
		add(payload.NextEpisodeToAir.SeasonNumber)
	}
	if payload.LastEpisodeToAir != nil {
		add(payload.LastEpisodeToAir.SeasonNumber)
	}
	// Une saison annoncée avec sa date, mais dont TMDB n'a pas encore fait le
	// « prochain épisode » : c'est le retour qu'on attend le plus.
	horizon := today.AddDate(0, 0, -60).Format("2006-01-02")
	for _, s := range payload.Seasons {
		if len(s.AirDate) == len("2006-01-02") && s.AirDate >= horizon {
			add(s.SeasonNumber)
		}
	}

	show := calendar.Show{Name: strings.TrimSpace(payload.Name)}
	if payload.PosterPath != nil {
		show.PosterPath = *payload.PosterPath
	}
	complete := true
	for _, n := range seasons {
		episodes := FetchTMDBSeasonEpisodes(tmdbID, n, lang)
		if episodes == nil {
			complete = false // saison injoignable : on montre le reste sans le figer
		}
		for _, ep := range episodes {
			show.Episodes = append(show.Episodes, calendar.Episode{
				Season:    n,
				Number:    ep.Number,
				Name:      ep.Name,
				AirDate:   ep.AirDate,
				StillPath: ep.StillPath,
				Type:      ep.Type,
			})
		}
	}
	if complete {
		calendarShowCache.Put(calendarCacheKey(tmdbID, lang), show)
	}
	return show, true
}

// fetchCalendarMovie lit la sortie d'un film dans le pays de la langue
// demandée (fr-FR → FR).
func fetchCalendarMovie(tmdbID int, lang mediaLanguage) (calendar.Movie, bool) {
	if tmdbID <= 0 || tmdbRequestAPIKey() == "" {
		return calendar.Movie{}, false
	}
	locale := lang.tmdbLocale()
	resp, err := tmdb.Get(httpx.Standard, fmt.Sprintf("/movie/%d?language=%s&append_to_response=release_dates", tmdbID, locale))
	if err != nil {
		return calendar.Movie{}, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return calendar.Movie{}, false
	}
	var payload struct {
		Title        string  `json:"title"`
		PosterPath   *string `json:"poster_path"`
		ReleaseDate  string  `json:"release_date"`
		ReleaseDates struct {
			Results []struct {
				Country string `json:"iso_3166_1"`
				Dates   []struct {
					Type int    `json:"type"`
					Date string `json:"release_date"`
				} `json:"release_dates"`
			} `json:"results"`
		} `json:"release_dates"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return calendar.Movie{}, false
	}
	var releases []calendar.Release
	for _, country := range payload.ReleaseDates.Results {
		for _, d := range country.Dates {
			releases = append(releases, calendar.Release{Country: country.Country, Type: d.Type, Date: d.Date})
		}
	}
	movie := calendar.Movie{Name: strings.TrimSpace(payload.Title)}
	if payload.PosterPath != nil {
		movie.PosterPath = *payload.PosterPath
	}
	movie.ReleaseDate, movie.ReleaseType = calendar.PickRelease(releases, localeCountry(locale), payload.ReleaseDate)
	calendarMovieCache.Put(calendarCacheKey(tmdbID, lang), movie)
	return movie, true
}

// localeCountry rend le pays d'une locale TMDB (« fr-FR » → « FR »), vide
// quand elle n'en porte pas.
func localeCountry(locale string) string {
	if i := strings.IndexByte(locale, '-'); i >= 0 && i+1 < len(locale) {
		return strings.ToUpper(locale[i+1:])
	}
	return ""
}
