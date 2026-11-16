package titleindex

import (
	"bytes"
	"compress/gzip"
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func gz(t *testing.T, lines ...string) []byte {
	t.Helper()
	var buf bytes.Buffer
	w := gzip.NewWriter(&buf)
	if _, err := w.Write([]byte(strings.Join(lines, "\n") + "\n")); err != nil {
		t.Fatalf("gzip : %v", err)
	}
	if err := w.Close(); err != nil {
		t.Fatalf("gzip : %v", err)
	}
	return buf.Bytes()
}

// Des lignes tirées de l'export du 15/11/2026, plus les cas que le filtre
// doit écarter.
func exportFiles(t *testing.T) map[string][]byte {
	return map[string][]byte{
		"movie_ids": gz(t,
			`{"adult":false,"id":268,"original_title":"Batman","popularity":11.4,"video":false}`,
			`{"adult":false,"id":414906,"original_title":"The Batman","popularity":27.76,"video":false}`,
			`{"adult":false,"id":272,"original_title":"Batman Begins","popularity":19.26,"video":false}`,
			`{"adult":false,"id":155,"original_title":"The Dark Knight","popularity":83.28,"video":false}`,
			`{"adult":false,"id":2,"original_title":"Batman inconnu","popularity":0.6,"video":false}`,
			`{"adult":false,"id":3,"original_title":"Batman bande-annonce","popularity":9,"video":true}`,
			`{"adult":true,"id":4,"original_title":"Batman pour adultes","popularity":9,"video":false}`,
			`{"adult":false,"id":194,"original_title":"Le Fabuleux Destin d'Amélie Poulain","popularity":13.89,"video":false}`,
		),
		"tv_series_ids": gz(t,
			`{"id":2287,"original_name":"Batman","popularity":42.69}`,
			`{"id":1,"original_name":"Bat Masterson","popularity":17.92}`,
			`{"id":2,"original_name":"Batang Quiapo","popularity":56.79}`,
			`{"id":5,"original_name":"Bat de quartier","popularity":1.5}`,
		),
	}
}

// exportServer sert les fichiers de files pour le jour day, et 403 (comme
// files.tmdb.org) pour tout autre. Il compte les téléchargements.
func exportServer(t *testing.T, files map[string][]byte, day time.Time, calls *int) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*calls++
		for name, body := range files {
			if r.URL.Path == "/"+name+"_"+day.Format("01_02_2006")+".json.gz" {
				_, _ = w.Write(body)
				return
			}
		}
		w.WriteHeader(http.StatusForbidden)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func openTestIndex(t *testing.T) *Index {
	t.Helper()
	ix, err := Open(filepath.Join(t.TempDir(), "titles.db"))
	if err != nil {
		t.Fatalf("ouverture de l'index : %v", err)
	}
	t.Cleanup(func() { ix.Close() })
	return ix
}

func filledIndex(t *testing.T) *Index {
	t.Helper()
	ix := openTestIndex(t)
	day := time.Date(2026, 11, 15, 0, 0, 0, 0, time.UTC)
	calls := 0
	srv := exportServer(t, exportFiles(t), day, &calls)
	r := Refresher{Index: ix, Client: srv.Client(), BaseURL: srv.URL + "/"}
	if _, err := r.Refresh(context.Background(), day); err != nil {
		t.Fatalf("remplissage : %v", err)
	}
	return ix
}

func titles(hits []Hit) []string {
	out := make([]string, len(hits))
	for i, h := range hits {
		out[i] = h.MediaType + ":" + h.Title
	}
	return out
}

func TestIndexKeepsOnlyKnownTitlesAboveEachThreshold(t *testing.T) {
	ix := filledIndex(t)
	hits, err := ix.Suggest(context.Background(), "bat", "", 50)
	if err != nil {
		t.Fatalf("suggestion : %v", err)
	}
	got := strings.Join(titles(hits), "|")
	for _, dropped := range []string{"Batman inconnu", "bande-annonce", "pour adultes", "Bat de quartier"} {
		if strings.Contains(got, dropped) {
			t.Fatalf("%q est sous le seuil, une vidéo ou pour adultes : il ne doit pas être indexé (%s)", dropped, got)
		}
	}
	if day, _ := ix.BuiltFor(context.Background()); day != "2026-11-15" {
		t.Fatalf("jour de l'index %q, attendu 2026-11-15", day)
	}
}

// Le cas qui a lancé l'index : « bat » doit proposer les Batman connus, et
// la popularité gonflée des séries ne doit pas les faire passer derrière
// « Batang Quiapo ».
func TestIndexSuggestsKnownTitlesStartingWithTheQuery(t *testing.T) {
	ix := filledIndex(t)
	hits, err := ix.Suggest(context.Background(), "bat", "", 10)
	if err != nil {
		t.Fatalf("suggestion : %v", err)
	}
	got := titles(hits)
	if len(got) < 2 || got[0] != "movie:The Batman" || got[1] != "movie:Batman Begins" {
		t.Fatalf("les films Batman les plus connus d'abord : %v", got)
	}
	// L'index n'a pas les votes : « Batang Quiapo » peut passer devant le
	// Batman de 1989, la recherche les départage ensuite. « Bat Masterson »
	// reste derrière tous les Batman.
	last := -1
	for i, h := range got {
		if strings.Contains(h, "Batman") {
			last = i
		}
	}
	if masterson := indexOf(got, "tv:Bat Masterson"); masterson < last {
		t.Fatalf("« Bat Masterson » doit suivre tous les Batman : %v", got)
	}
}

func TestIndexMatchesEveryWordPrefixAndIgnoresAccents(t *testing.T) {
	ix := filledIndex(t)
	for query, want := range map[string]string{
		"dark kni": "movie:The Dark Knight",
		"amelie":   "movie:Le Fabuleux Destin d'Amélie Poulain",
		"Amélie P": "movie:Le Fabuleux Destin d'Amélie Poulain",
	} {
		hits, err := ix.Suggest(context.Background(), query, "", 3)
		if err != nil {
			t.Fatalf("suggestion %q : %v", query, err)
		}
		if len(hits) == 0 || titles(hits)[0] != want {
			t.Fatalf("%q : %v, attendu %s en tête", query, titles(hits), want)
		}
	}
}

func TestIndexFiltersByMediaType(t *testing.T) {
	ix := filledIndex(t)
	hits, err := ix.Suggest(context.Background(), "batman", "tv", 10)
	if err != nil {
		t.Fatalf("suggestion : %v", err)
	}
	if len(hits) != 1 || hits[0].ID != 2287 {
		t.Fatalf("seules les séries : %v", titles(hits))
	}
}

// Une seule lettre toucherait presque tout l'index : rien n'est suggéré.
func TestIndexSuggestsNothingForASingleLetterOrAnEmptyIndex(t *testing.T) {
	ix := filledIndex(t)
	if hits, err := ix.Suggest(context.Background(), "b", "", 10); err != nil || len(hits) != 0 {
		t.Fatalf("une lettre : %v, %v", titles(hits), err)
	}
	empty := openTestIndex(t)
	if hits, err := empty.Suggest(context.Background(), "batman", "", 10); err != nil || len(hits) != 0 {
		t.Fatalf("index vide : %v, %v", titles(hits), err)
	}
}

// Un téléchargement coupé (ici, les séries absentes) laisse l'index de la
// veille entier : les films et les séries changent ensemble.
func TestFailedRefreshKeepsThePreviousIndex(t *testing.T) {
	ix := filledIndex(t)
	day := time.Date(2026, 11, 16, 0, 0, 0, 0, time.UTC)
	files := exportFiles(t)
	delete(files, "tv_series_ids")
	calls := 0
	srv := exportServer(t, files, day, &calls)
	r := Refresher{Index: ix, Client: srv.Client(), BaseURL: srv.URL + "/"}
	if _, err := r.Refresh(context.Background(), day); err == nil {
		t.Fatal("un export de séries absent doit faire échouer le rafraîchissement")
	}
	if built, _ := ix.BuiltFor(context.Background()); built != "2026-11-15" {
		t.Fatalf("jour de l'index %q, attendu celui de la veille", built)
	}
	if hits, _ := ix.Suggest(context.Background(), "batman", "tv", 10); len(hits) != 1 {
		t.Fatalf("les séries de la veille doivent rester : %v", titles(hits))
	}
}

// Avant 9 h UTC l'export du jour n'est pas sûr d'être publié ; s'il manque,
// on prend celui de la veille, et l'on ne retélécharge pas un jour déjà là.
func TestRefreshFallsBackToYesterdayAndSkipsADayAlreadyIndexed(t *testing.T) {
	ix := openTestIndex(t)
	yesterday := time.Date(2026, 11, 15, 0, 0, 0, 0, time.UTC)
	calls := 0
	srv := exportServer(t, exportFiles(t), yesterday, &calls)
	r := Refresher{Index: ix, Client: srv.Client(), BaseURL: srv.URL + "/"}
	now := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)

	r.refreshIfStale(context.Background(), now)
	if built, _ := ix.BuiltFor(context.Background()); built != "2026-11-15" {
		t.Fatalf("jour de l'index %q, attendu la veille", built)
	}
	before := calls
	r.refreshIfStale(context.Background(), now.Add(time.Hour))
	// Le jour même est redemandé (il peut avoir été publié), pas la veille.
	if calls-before != 1 {
		t.Fatalf("%d téléchargements, attendu un seul essai pour le jour même", calls-before)
	}
}

func TestExportDayWaitsForThePublication(t *testing.T) {
	cases := map[time.Time]string{
		time.Date(2026, 11, 16, 8, 59, 0, 0, time.UTC): "2026-11-15",
		time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC):  "2026-11-16",
	}
	for now, want := range cases {
		if got := exportDay(now).Format("2006-01-02"); got != want {
			t.Errorf("exportDay(%s) = %s, attendu %s", now, got, want)
		}
	}
}

func indexOf(list []string, want string) int {
	for i, v := range list {
		if v == want {
			return i
		}
	}
	return -1
}
