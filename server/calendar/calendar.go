// Package calendar assemble le calendrier personnel des sorties (« À venir »).
//
// Il ne lit ni la base ni TMDB : l'appelant lui donne les titres qui
// intéressent le compte (regardés, suivis, demandés, présents sur le
// serveur), ses choix de suivi, les dates connues et ce que la bibliothèque
// détient déjà. Le paquet décide seul qui apparaît, pour quelle raison, et
// sous quelle forme. Voir l'ADR 2026-11-27-tsuky-calendrier-sorties-serveur.
package calendar

import (
	"fmt"
	"sort"
	"strings"
)

// Kind distingue une série d'un film.
type Kind string

const (
	KindShow  Kind = "show"
	KindMovie Kind = "movie"
)

// Source dit pourquoi un titre est dans le calendrier. L'ordre des
// constantes est aussi celui de la priorité quand plusieurs raisons
// s'appliquent : un suivi explicite l'emporte sur tout le reste, et « vous
// regardez » dit plus que « vous avez demandé ».
type Source string

const (
	SourceFollowed Source = "followed"
	SourceWatching Source = "watching"
	SourceRequest  Source = "request"
	SourceServer   Source = "server"
)

var sourceRank = map[Source]int{
	SourceFollowed: 0,
	SourceWatching: 1,
	SourceRequest:  2,
	SourceServer:   3,
}

// Interest est un titre qui concerne le compte, et la raison pour laquelle.
type Interest struct {
	Kind   Kind
	TMDBID int
	Source Source
	// MediaID est la fiche de la bibliothèque, 0 quand le serveur n'a pas le titre.
	MediaID   int
	Title     string
	PosterURL string
}

// Choice est le choix explicite d'un compte sur une série : la suivre, ou la
// retirer du calendrier même si elle y entrait d'elle-même.
type Choice bool

const (
	Follow Choice = true
	Mute   Choice = false
)

// Merge garde un intérêt par titre, celui de la raison la plus forte, puis
// applique les choix du compte : une série retirée disparaît quelle que soit
// sa raison, une série suivie à la main apparaît même si rien d'autre ne l'y
// mettait. Les choix ne portent que sur les séries ; le bouton « Suivre »
// n'existe pas pour un film.
func Merge(candidates []Interest, choices map[int]Choice) []Interest {
	type key struct {
		kind Kind
		id   int
	}
	best := map[key]Interest{}
	order := []key{}
	for _, c := range candidates {
		if c.TMDBID <= 0 {
			continue
		}
		k := key{c.Kind, c.TMDBID}
		current, seen := best[k]
		if !seen {
			order = append(order, k)
			best[k] = c
			continue
		}
		if sourceRank[c.Source] < sourceRank[current.Source] {
			c.MediaID = firstNonZero(c.MediaID, current.MediaID)
			c.Title = firstNonEmpty(c.Title, current.Title)
			c.PosterURL = firstNonEmpty(c.PosterURL, current.PosterURL)
			best[k] = c
			continue
		}
		current.MediaID = firstNonZero(current.MediaID, c.MediaID)
		current.Title = firstNonEmpty(current.Title, c.Title)
		current.PosterURL = firstNonEmpty(current.PosterURL, c.PosterURL)
		best[k] = current
	}

	for id, choice := range choices {
		k := key{KindShow, id}
		current, seen := best[k]
		switch {
		case choice == Mute:
			delete(best, k)
		case !seen:
			order = append(order, k)
			best[k] = Interest{Kind: KindShow, TMDBID: id, Source: SourceFollowed}
		default:
			current.Source = SourceFollowed
			best[k] = current
		}
	}

	out := make([]Interest, 0, len(best))
	for _, k := range order {
		if interest, ok := best[k]; ok {
			out = append(out, interest)
			delete(best, k) // un suivi ajouté deux fois dans order ne sort qu'une fois
		}
	}
	return out
}

// Episode est un épisode tel que TMDB l'annonce.
type Episode struct {
	Season    int
	Number    int
	Name      string
	AirDate   string // AAAA-MM-JJ, vide quand TMDB ne la connaît pas encore
	StillPath string
	// Type est l'episode_type de TMDB : « finale », « mid_season »,
	// « standard ».
	Type string
}

// Show est le programme d'une série.
type Show struct {
	Name       string
	PosterPath string
	Episodes   []Episode
}

// Movie est la sortie d'un film.
type Movie struct {
	Name        string
	PosterPath  string
	ReleaseDate string // AAAA-MM-JJ
	// ReleaseType vaut « digital », « physical » ou « theatrical » : la
	// sortie qu'on retient, celle qui permet de le voir chez soi d'abord.
	ReleaseType string
}

// Presence est ce que la bibliothèque détient déjà, pour dire « Disponible »
// et lancer la lecture sans passer par la fiche.
type Presence struct {
	// Episodes : identifiant TMDB de la série → (saison, épisode) → média.
	Episodes map[int]map[[2]int]int
	// Movies : identifiant TMDB du film → média.
	Movies map[int]int
}

// Entry est une sortie du calendrier, telle que l'app la lit.
type Entry struct {
	ID             string `json:"id"`
	Kind           Kind   `json:"kind"`
	Source         Source `json:"source"`
	TMDBID         int    `json:"tmdb_id"`
	MediaID        int    `json:"media_id"`
	EpisodeMediaID int    `json:"episode_media_id"`
	Title          string `json:"title"`
	AirDate        string `json:"air_date"`
	SeasonNumber   int    `json:"season_number"`
	EpisodeNumber  int    `json:"episode_number"`
	EpisodeName    string `json:"episode_name"`
	// EpisodeType vaut « premiere » (premier épisode d'une saison),
	// « finale » ou « » : l'app en fait « Retour » ou « Finale ».
	EpisodeType string `json:"episode_type"`
	ReleaseType string `json:"release_type"`
	PosterURL   string `json:"poster_url"`
	StillURL    string `json:"still_url"`
	Ready       bool   `json:"ready"`
}

// FollowedShow est une série du calendrier, pour la feuille « Séries
// suivies ».
type FollowedShow struct {
	TMDBID        int    `json:"tmdb_id"`
	MediaID       int    `json:"media_id"`
	Title         string `json:"title"`
	Source        Source `json:"source"`
	PosterURL     string `json:"poster_url"`
	NextAirDate   string `json:"next_air_date"`
	NextSeason    int    `json:"next_season"`
	NextEpisode   int    `json:"next_episode"`
	NextEpisodeID string `json:"next_entry_id"`
}

const tmdbImage = "https://image.tmdb.org/t/p/"

// TMDBImage rend l'URL d'une image TMDB à la largeur donnée, vide sans chemin.
func TMDBImage(path, size string) string {
	if path == "" {
		return ""
	}
	if strings.HasPrefix(path, "http") {
		return path
	}
	return tmdbImage + size + path
}

// Build rend les sorties de [from, to] (AAAA-MM-JJ, bornes incluses), triées
// par date puis par titre. Un titre dont on ne connaît pas le programme est
// absent, sans erreur : TMDB injoignable ne vide pas le calendrier des autres.
func Build(interests []Interest, shows map[int]Show, movies map[int]Movie, presence Presence, from, to string) []Entry {
	entries := []Entry{}
	for _, it := range interests {
		switch it.Kind {
		case KindShow:
			show, ok := shows[it.TMDBID]
			if !ok {
				continue
			}
			title := firstNonEmpty(it.Title, show.Name)
			poster := firstNonEmpty(it.PosterURL, TMDBImage(show.PosterPath, "w342"))
			for _, ep := range show.Episodes {
				if !inRange(ep.AirDate, from, to) {
					continue
				}
				mediaID := presence.Episodes[it.TMDBID][[2]int{ep.Season, ep.Number}]
				entries = append(entries, Entry{
					ID:             fmt.Sprintf("tv:%d:s%de%d", it.TMDBID, ep.Season, ep.Number),
					Kind:           KindShow,
					Source:         it.Source,
					TMDBID:         it.TMDBID,
					MediaID:        it.MediaID,
					EpisodeMediaID: mediaID,
					Title:          title,
					AirDate:        ep.AirDate,
					SeasonNumber:   ep.Season,
					EpisodeNumber:  ep.Number,
					EpisodeName:    ep.Name,
					EpisodeType:    episodeType(ep),
					PosterURL:      poster,
					StillURL:       TMDBImage(ep.StillPath, "w300"),
					Ready:          mediaID > 0,
				})
			}
		case KindMovie:
			movie, ok := movies[it.TMDBID]
			if !ok || !inRange(movie.ReleaseDate, from, to) {
				continue
			}
			mediaID := presence.Movies[it.TMDBID]
			entries = append(entries, Entry{
				ID:             fmt.Sprintf("movie:%d", it.TMDBID),
				Kind:           KindMovie,
				Source:         it.Source,
				TMDBID:         it.TMDBID,
				MediaID:        firstNonZero(it.MediaID, mediaID),
				EpisodeMediaID: 0,
				Title:          firstNonEmpty(it.Title, movie.Name),
				AirDate:        movie.ReleaseDate,
				ReleaseType:    movie.ReleaseType,
				PosterURL:      firstNonEmpty(it.PosterURL, TMDBImage(movie.PosterPath, "w342")),
				Ready:          mediaID > 0,
			})
		}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		a, b := entries[i], entries[j]
		if a.AirDate != b.AirDate {
			return a.AirDate < b.AirDate
		}
		if a.Title != b.Title {
			return a.Title < b.Title
		}
		if a.SeasonNumber != b.SeasonNumber {
			return a.SeasonNumber < b.SeasonNumber
		}
		return a.EpisodeNumber < b.EpisodeNumber
	})
	return entries
}

// Followed rend les séries du calendrier avec leur prochain épisode à partir
// de today (AAAA-MM-JJ), triées par titre.
func Followed(interests []Interest, shows map[int]Show, today string) []FollowedShow {
	out := []FollowedShow{}
	for _, it := range interests {
		if it.Kind != KindShow {
			continue
		}
		show := shows[it.TMDBID]
		item := FollowedShow{
			TMDBID:    it.TMDBID,
			MediaID:   it.MediaID,
			Title:     firstNonEmpty(it.Title, show.Name),
			Source:    it.Source,
			PosterURL: firstNonEmpty(it.PosterURL, TMDBImage(show.PosterPath, "w342")),
		}
		if item.Title == "" {
			continue // ni la bibliothèque ni TMDB ne savent nommer la série
		}
		for _, ep := range show.Episodes {
			if ep.AirDate == "" || ep.AirDate < today {
				continue
			}
			if item.NextAirDate == "" || ep.AirDate < item.NextAirDate {
				item.NextAirDate = ep.AirDate
				item.NextSeason = ep.Season
				item.NextEpisode = ep.Number
				item.NextEpisodeID = fmt.Sprintf("tv:%d:s%de%d", it.TMDBID, ep.Season, ep.Number)
			}
		}
		out = append(out, item)
	}
	sort.SliceStable(out, func(i, j int) bool {
		return strings.ToLower(out[i].Title) < strings.ToLower(out[j].Title)
	})
	return out
}

func episodeType(ep Episode) string {
	switch {
	case ep.Type == "finale":
		return "finale"
	case ep.Number == 1:
		return "premiere"
	default:
		return ""
	}
}

func inRange(date, from, to string) bool {
	if len(date) != len("2006-01-02") {
		return false
	}
	return date >= from && date <= to
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

func firstNonZero(values ...int) int {
	for _, v := range values {
		if v != 0 {
			return v
		}
	}
	return 0
}
