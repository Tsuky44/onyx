package calendar

import (
	"reflect"
	"testing"
)

func TestMergeKeepsTheStrongestReasonPerTitle(t *testing.T) {
	got := Merge([]Interest{
		{Kind: KindShow, TMDBID: 1, Source: SourceServer, MediaID: 10, PosterURL: "/p/10"},
		{Kind: KindShow, TMDBID: 1, Source: SourceRequest, Title: "Cendres"},
		{Kind: KindShow, TMDBID: 1, Source: SourceWatching},
	}, nil)
	want := []Interest{{Kind: KindShow, TMDBID: 1, Source: SourceWatching, MediaID: 10, Title: "Cendres", PosterURL: "/p/10"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Merge = %+v, want %+v", got, want)
	}
}

func TestMergeKeepsAShowAndAMovieWithTheSameTMDBID(t *testing.T) {
	got := Merge([]Interest{
		{Kind: KindShow, TMDBID: 7, Source: SourceWatching},
		{Kind: KindMovie, TMDBID: 7, Source: SourceRequest},
	}, nil)
	if len(got) != 2 {
		t.Fatalf("les identifiants TMDB des films et des séries sont deux espaces distincts, got %+v", got)
	}
}

func TestMergeMutedShowNeverComesBackOnItsOwn(t *testing.T) {
	got := Merge([]Interest{
		{Kind: KindShow, TMDBID: 1, Source: SourceWatching},
		{Kind: KindShow, TMDBID: 2, Source: SourceRequest},
	}, map[int]Choice{1: Mute})
	if len(got) != 1 || got[0].TMDBID != 2 {
		t.Fatalf("une série retirée doit rester retirée même si on la regarde, got %+v", got)
	}
}

func TestMergeManualFollowAddsAShowNothingElseBrings(t *testing.T) {
	got := Merge(nil, map[int]Choice{5: Follow})
	want := []Interest{{Kind: KindShow, TMDBID: 5, Source: SourceFollowed}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Merge = %+v, want %+v", got, want)
	}
}

func TestMergeManualFollowOverridesAnAutomaticReason(t *testing.T) {
	got := Merge([]Interest{{Kind: KindShow, TMDBID: 1, Source: SourceWatching, MediaID: 3}}, map[int]Choice{1: Follow})
	if len(got) != 1 || got[0].Source != SourceFollowed || got[0].MediaID != 3 {
		t.Fatalf("got %+v", got)
	}
}

func TestMergeChoicesNeverTouchMovies(t *testing.T) {
	got := Merge([]Interest{{Kind: KindMovie, TMDBID: 1, Source: SourceRequest}}, map[int]Choice{1: Mute})
	if len(got) != 1 || got[0].Kind != KindMovie {
		t.Fatalf("retirer la série 1 ne doit pas retirer le film 1, got %+v", got)
	}
}

func TestBuildKeepsOnlyTheWindowAndMarksWhatTheServerHolds(t *testing.T) {
	interests := []Interest{
		{Kind: KindShow, TMDBID: 1, Source: SourceWatching, MediaID: 100, Title: "Les Veilleurs"},
		{Kind: KindMovie, TMDBID: 9, Source: SourceRequest},
		{Kind: KindShow, TMDBID: 2, Source: SourceServer}, // programme inconnu : absent
	}
	shows := map[int]Show{1: {Name: "The Watchers", PosterPath: "/w.jpg", Episodes: []Episode{
		{Season: 2, Number: 8, AirDate: "2026-11-20"},
		{Season: 2, Number: 9, AirDate: "2026-11-27", StillPath: "/s9.jpg"},
		{Season: 2, Number: 10, AirDate: "2026-12-04", Type: "finale"},
		{Season: 3, Number: 1, AirDate: ""},
	}}}
	movies := map[int]Movie{9: {Name: "Brume", PosterPath: "/b.jpg", ReleaseDate: "2026-12-01", ReleaseType: "digital"}}
	presence := Presence{Episodes: map[int]map[[2]int]int{1: {{2, 9}: 555}}}

	got := Build(interests, shows, movies, presence, "2026-11-27", "2026-12-31")
	if len(got) != 3 {
		t.Fatalf("Build = %+v", got)
	}
	ep9, movie, finale := got[0], got[1], got[2]
	if ep9.ID != "tv:1:s2e9" || !ep9.Ready || ep9.EpisodeMediaID != 555 || ep9.Title != "Les Veilleurs" ||
		ep9.StillURL != "https://image.tmdb.org/t/p/w300/s9.jpg" || ep9.PosterURL != "https://image.tmdb.org/t/p/w342/w.jpg" {
		t.Errorf("épisode du jour = %+v", ep9)
	}
	if movie.ID != "movie:9" || movie.Title != "Brume" || movie.ReleaseType != "digital" || movie.Ready {
		t.Errorf("film = %+v", movie)
	}
	if finale.EpisodeType != "finale" || finale.Ready {
		t.Errorf("finale = %+v", finale)
	}
}

func TestBuildCallsTheFirstEpisodeOfASeasonAPremiere(t *testing.T) {
	got := Build(
		[]Interest{{Kind: KindShow, TMDBID: 1, Source: SourceRequest}},
		map[int]Show{1: {Name: "Cendres", Episodes: []Episode{{Season: 3, Number: 1, AirDate: "2026-11-28"}}}},
		nil, Presence{}, "2026-11-01", "2026-11-30")
	if len(got) != 1 || got[0].EpisodeType != "premiere" {
		t.Fatalf("got %+v", got)
	}
}

func TestFollowedGivesTheNextEpisodeFromToday(t *testing.T) {
	got := Followed(
		[]Interest{
			{Kind: KindShow, TMDBID: 2, Source: SourceFollowed},
			{Kind: KindShow, TMDBID: 1, Source: SourceWatching, Title: "alpha"},
			{Kind: KindMovie, TMDBID: 3, Source: SourceRequest, Title: "Film"},
		},
		map[int]Show{
			1: {Episodes: []Episode{{Season: 1, Number: 1, AirDate: "2026-11-01"}, {Season: 1, Number: 3, AirDate: "2026-12-10"}, {Season: 1, Number: 2, AirDate: "2026-11-27"}}},
			2: {Name: "Zénith"},
		},
		"2026-11-27")
	if len(got) != 2 {
		t.Fatalf("les films n'ont pas leur place dans « Séries suivies », got %+v", got)
	}
	if got[0].Title != "alpha" || got[0].NextAirDate != "2026-11-27" || got[0].NextEpisode != 2 || got[0].NextEpisodeID != "tv:1:s1e2" {
		t.Errorf("alpha = %+v", got[0])
	}
	if got[1].Title != "Zénith" || got[1].NextAirDate != "" {
		t.Errorf("une série sans date reste listée pour pouvoir la retirer, got %+v", got[1])
	}
}
