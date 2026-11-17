package mediahub

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// Le contrat avec Overseerr et Jellyseerr, vu d'Onyx (ADR-0136). Le faux
// Seerr sert les exemples de contract/seerr/ : ce qu'ils écrivent doit se lire
// ici, et ce qu'Onyx leur envoie doit valoir le fichier.

const seerrContractDir = "../../contract/seerr"

func seerrContract(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(seerrContractDir, name))
	if err != nil {
		t.Fatalf("contract/seerr/%s : %v", name, err)
	}
	return data
}

// fakeSeerr retient chaque appel : « MÉTHODE chemin?requête as=<X-Api-User> ».
type fakeSeerr struct {
	mu    sync.Mutex
	calls []string
}

func (f *fakeSeerr) seen() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string{}, f.calls...)
}

func (f *fakeSeerr) count(prefix string) int {
	n := 0
	for _, call := range f.seen() {
		if strings.HasPrefix(call, prefix) {
			n++
		}
	}
	return n
}

// newFakeSeerr monte un faux Seerr : les routes données d'abord (« GET
// /request »), sinon les exemples du contrat. La clé est « cle ».
func newFakeSeerr(t *testing.T, service Service, routes map[string]http.HandlerFunc) (Client, *fakeSeerr) {
	t.Helper()
	fake := &fakeSeerr{}
	files := map[string]string{
		"GET /status":          "status.json",
		"GET /settings/public": "settings_public.json",
		"GET /auth/me":         "auth_me.json",
		"GET /user":            "users.json",
		"GET /request":         "requests.json",
		"GET /movie/603":       "movie.json",
		"GET /tv/1399":         "tv.json",
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, SeerrPath)
		key := r.Method + " " + path
		call := key
		if r.URL.RawQuery != "" {
			call += "?" + r.URL.RawQuery
		}
		fake.mu.Lock()
		fake.calls = append(fake.calls, call+" as="+r.Header.Get("X-Api-User"))
		fake.mu.Unlock()

		public := key == "GET /status" || key == "GET /settings/public"
		if !public && r.Header.Get("X-Api-Key") != "cle" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"status":403,"error":"You do not have permission to access this endpoint"}`))
			return
		}
		if handler, ok := routes[key]; ok {
			handler(w, r)
			return
		}
		if file, ok := files[key]; ok {
			_, _ = w.Write(seerrContract(t, file))
			return
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"message":"Unable to retrieve movie."}`))
	}))
	t.Cleanup(server.Close)
	Reset()
	t.Cleanup(Reset)
	return Client{BaseURL: server.URL, APIKey: "cle", HTTP: &http.Client{Timeout: 5 * time.Second}, Service: service, Language: "fr-FR"}, fake
}

func TestParseServiceKeepsMediaHubForAnInstallFromBeforeTheChoice(t *testing.T) {
	cases := []struct {
		raw   string
		want  Service
		valid bool
	}{
		{"", ServiceMediaHub, true},
		{"mediahub", ServiceMediaHub, true},
		{" Jellyseerr ", ServiceJellyseerr, true},
		{"overseerr", ServiceOverseerr, true},
		{"ombi", ServiceMediaHub, false},
	}
	for _, c := range cases {
		got, valid := ParseService(c.raw)
		if got != c.want || valid != c.valid {
			t.Errorf("ParseService(%q) = %q, %v ; attendu %q, %v", c.raw, got, valid, c.want, c.valid)
		}
	}
	if ServiceMediaHub.Seerr() || !ServiceOverseerr.Seerr() || !ServiceJellyseerr.Seerr() {
		t.Fatal("Seerr() ne range pas les services comme attendu")
	}
}

func TestSeerrRequestStatusFollowsTheDecisionThenTheTitle(t *testing.T) {
	cases := []struct {
		request, media int
		want           string
	}{
		{1, 2, "pending"},
		{3, 1, "declined"},
		{2, 1, "approved"},
		{2, 3, "processing"},
		{2, 4, "partial"},
		{2, 5, "available"},
		// Jellyseerr : échouée chez Radarr, terminée, titre supprimé depuis.
		{4, 1, "approved"},
		{5, 5, "available"},
		{2, 7, "approved"},
	}
	for _, c := range cases {
		if got := seerrRequestStatus(c.request, c.media); got != c.want {
			t.Errorf("seerrRequestStatus(%d, %d) = %q, attendu %q", c.request, c.media, got, c.want)
		}
	}
}

func TestSeerrAccountIsTheOneNamedLikeTheOnyxAccount(t *testing.T) {
	client, _ := newFakeSeerr(t, ServiceJellyseerr, nil)

	// « lea » porte le nom Jellyfin « Lea » : un compte qui ne fait que demander.
	lea, err := client.Access(context.Background(), Account{ID: 7, Username: "lea"})
	if err != nil {
		t.Fatalf("Access: %v", err)
	}
	if lea.Service != "jellyseerr" || lea.Version != "2.7.3" || !lea.Linked || !lea.SeasonChoice ||
		!lea.Can.Request || lea.Can.ReadAllRequests || lea.Can.Moderate || lea.Can.Delete || lea.Can.InteractiveSearch {
		t.Fatalf("droits de lea = %+v", lea)
	}

	// « hugo » voit les demandes des autres sans pouvoir les décider.
	hugo, err := client.Access(context.Background(), Account{ID: 8, Username: "HUGO"})
	if err != nil {
		t.Fatalf("Access: %v", err)
	}
	if !hugo.Linked || !hugo.Can.ReadAllRequests || hugo.Can.Moderate {
		t.Fatalf("droits de hugo = %+v", hugo)
	}
}

func TestSeerrAccountWithoutNamesakeActsAsTheKeysAccount(t *testing.T) {
	client, fake := newFakeSeerr(t, ServiceOverseerr, nil)
	access, err := client.Access(context.Background(), Account{ID: 9, Username: "inconnue"})
	if err != nil {
		t.Fatalf("Access: %v", err)
	}
	// Le compte de la clé est administrateur : ses droits, mais pas lié.
	if access.Service != "overseerr" || access.Linked || !access.Can.Request || !access.Can.Moderate {
		t.Fatalf("droits = %+v", access)
	}

	if _, err := client.Requests(context.Background(), Account{ID: 9, Username: "inconnue"}, ScopeMine); err != nil {
		t.Fatalf("Requests: %v", err)
	}
	if fake.count("GET /request?filter=all&requestedBy=1&") != 1 {
		t.Fatalf("« mes demandes » ne lit pas celles du compte de la clé : %v", fake.seen())
	}
}

func TestSeerrAccountsAreReadOnceThenRemembered(t *testing.T) {
	client, fake := newFakeSeerr(t, ServiceJellyseerr, nil)
	for i := 0; i < 3; i++ {
		if _, err := client.Access(context.Background(), Account{Username: "lea"}); err != nil {
			t.Fatalf("Access: %v", err)
		}
	}
	if fake.count("GET /user") != 1 || fake.count("GET /auth/me") != 1 {
		t.Fatalf("les comptes se relisent à chaque appel : %v", fake.seen())
	}
}

func TestSeerrRequestsComeAsLotsWithTitlesAndSeasonStates(t *testing.T) {
	client, fake := newFakeSeerr(t, ServiceJellyseerr, nil)
	lots, err := client.Requests(context.Background(), Account{ID: 1, Username: "admin"}, ScopeAll)
	if err != nil {
		t.Fatalf("Requests: %v", err)
	}
	if len(lots) != 4 {
		t.Fatalf("lots = %+v", lots)
	}

	// Un film en attente dont la fiche ne répond pas : la demande se montre.
	pending := lots[0]
	if pending.Status != "pending" || pending.Title != "TMDB 438631" || pending.Requester != "hugo" ||
		len(pending.RequestIDs) != 1 || pending.RequestIDs[0] != 14 {
		t.Fatalf("film en attente = %+v", pending)
	}

	// La série arrivée en partie : la fiche dit quelle saison est là.
	show := lots[1]
	if show.Title != "Game of Thrones" || show.PosterPath == nil || *show.PosterPath != "/got.jpg" ||
		show.Status != "partial" || show.Requester != "Lea" || len(show.RequestIDs) != 1 || show.RequestIDs[0] != 13 ||
		len(show.SeasonStatuses) != 2 ||
		show.SeasonStatuses[0] != (SeasonStatus{SeasonNumber: 1, Status: "available"}) ||
		show.SeasonStatuses[1] != (SeasonStatus{SeasonNumber: 2, Status: "processing"}) {
		t.Fatalf("série = %+v", show)
	}

	// Le film en téléchargement porte l'avancement de Radarr.
	movie := lots[2]
	if movie.Title != "Matrix" || movie.Status != "processing" || movie.Progress == nil || *movie.Progress != 75 ||
		movie.RequestedAt != "2026-11-14T09:00:00.000Z" {
		t.Fatalf("film en cours = %+v", movie)
	}
	if lots[3].Status != "declined" {
		t.Fatalf("film refusé = %+v", lots[3])
	}

	// Toutes les demandes, au nom du compte : Seerr juge ce qu'il peut lire.
	if fake.count("GET /request?filter=all&skip=0&sort=added&take=100 as=1") != 1 {
		t.Fatalf("appel de liste inattendu : %v", fake.seen())
	}
}

func TestSeerrMyRequestsAskOnlyForTheAccountsOwn(t *testing.T) {
	client, fake := newFakeSeerr(t, ServiceJellyseerr, nil)
	if _, err := client.Requests(context.Background(), Account{ID: 7, Username: "lea"}, ScopeMine); err != nil {
		t.Fatalf("Requests: %v", err)
	}
	if fake.count("GET /request?filter=all&requestedBy=2&skip=0&sort=added&take=100 as=2") != 1 {
		t.Fatalf("« mes demandes » ne nomme pas le compte : %v", fake.seen())
	}
}

func TestSeerrContractCreateTranslatesTheRequestAndActsAsTheAccount(t *testing.T) {
	var sent []byte
	client, fake := newFakeSeerr(t, ServiceJellyseerr, map[string]http.HandlerFunc{
		"POST /request": func(w http.ResponseWriter, r *http.Request) {
			sent, _ = io.ReadAll(r.Body)
			w.WriteHeader(http.StatusCreated)
			_, _ = w.Write([]byte(`{"id":16,"status":1}`))
		},
	})
	body := []byte(`{"tmdbId":1399,"mediaType":"tv","title":"Game of Thrones","posterPath":"/got.jpg","seasons":[1,2]}`)
	status, _, err := client.CreateRequest(context.Background(), Account{ID: 7, Username: "lea"}, body)
	if err != nil || status != http.StatusCreated {
		t.Fatalf("CreateRequest = %d, %v", status, err)
	}
	var got, want map[string]any
	if json.Unmarshal(sent, &got) != nil || json.Unmarshal(seerrContract(t, "request_create.json"), &want) != nil {
		t.Fatalf("corps illisible : %s", sent)
	}
	if len(got) != len(want) || got["mediaId"] != want["mediaId"] || got["mediaType"] != want["mediaType"] ||
		len(got["seasons"].([]any)) != 2 {
		t.Fatalf("corps envoyé = %s", sent)
	}
	if fake.count("POST /request as=2") != 1 {
		t.Fatalf("la demande ne part pas au nom de lea : %v", fake.seen())
	}

	// Une série sans saisons choisies se demande entière, un film sans saisons.
	if _, _, err := client.CreateRequest(context.Background(), Account{Username: "lea"}, []byte(`{"tmdbId":1399,"mediaType":"tv"}`)); err != nil {
		t.Fatalf("CreateRequest: %v", err)
	}
	if !strings.Contains(string(sent), `"seasons":"all"`) {
		t.Fatalf("série entière = %s", sent)
	}
	if _, _, err := client.CreateRequest(context.Background(), Account{Username: "lea"}, []byte(`{"tmdbId":603,"mediaType":"movie"}`)); err != nil {
		t.Fatalf("CreateRequest: %v", err)
	}
	if strings.Contains(string(sent), "seasons") {
		t.Fatalf("film = %s", sent)
	}
}

func TestSeerrContractCreateSaysARefusalInFrench(t *testing.T) {
	answer := http.StatusForbidden
	client, _ := newFakeSeerr(t, ServiceJellyseerr, map[string]http.HandlerFunc{
		"POST /request": func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(answer)
			if answer == http.StatusAccepted {
				_, _ = w.Write([]byte(`{"message":"No seasons available to request"}`))
				return
			}
			_, _ = w.Write(seerrContract(t, "request_refused.json"))
		},
	})
	body := []byte(`{"tmdbId":1399,"mediaType":"tv"}`)
	status, raw, err := client.CreateRequest(context.Background(), Account{Username: "lea"}, body)
	if err != nil || status != http.StatusForbidden || !strings.Contains(string(raw), "Quota de demandes atteint chez Jellyseerr") {
		t.Fatalf("quota = %d %s (%v)", status, raw, err)
	}

	// 202 chez Seerr : plus aucune saison à demander. Ce n'est pas un succès.
	answer = http.StatusAccepted
	status, raw, err = client.CreateRequest(context.Background(), Account{Username: "lea"}, body)
	if err != nil || status != http.StatusConflict || !strings.Contains(string(raw), "déjà demandées") {
		t.Fatalf("plus de saison = %d %s (%v)", status, raw, err)
	}

	if status, _, err := client.CreateRequest(context.Background(), Account{Username: "lea"}, []byte(`{"mediaType":"tv"}`)); err == nil || status != 0 {
		t.Fatalf("une demande sans titre est partie : %d", status)
	}
}

func TestSeerrContractAvailabilityReadsWhatIsHeldThenWhatIsRequested(t *testing.T) {
	client, _ := newFakeSeerr(t, ServiceOverseerr, nil)
	show, err := client.Availability(context.Background(), 1399, "tv")
	if err != nil {
		t.Fatalf("Availability: %v", err)
	}
	want := map[int]string{0: "unknown", 1: "available", 2: "processing", 3: "pending", 4: "unknown"}
	if show.Status != "partial" || len(show.Seasons) != len(want) {
		t.Fatalf("série = %+v", show)
	}
	for _, season := range show.Seasons {
		if season.Status != want[season.SeasonNumber] {
			t.Errorf("saison %d = %q, attendu %q", season.SeasonNumber, season.Status, want[season.SeasonNumber])
		}
	}
	if show.Seasons[1].TotalEpisodes != 10 {
		t.Fatalf("épisodes de la saison 1 = %d", show.Seasons[1].TotalEpisodes)
	}

	movie, err := client.Availability(context.Background(), 603, "movie")
	if err != nil || movie.Status != "processing" || len(movie.Seasons) != 0 {
		t.Fatalf("film = %+v (%v)", movie, err)
	}
	// Un titre que Seerr ne trouve pas n'est pas une panne.
	unknown, err := client.Availability(context.Background(), 999, "movie")
	if err != nil || unknown.Status != "unknown" {
		t.Fatalf("titre inconnu = %+v (%v)", unknown, err)
	}
}

func TestSeerrCatalogPageReadsEachCardOnceThenRemembers(t *testing.T) {
	client, fake := newFakeSeerr(t, ServiceJellyseerr, nil)
	items := []BatchItem{{TMDBID: 603, MediaType: "movie"}, {TMDBID: 1399, MediaType: "tv"}, {TMDBID: 999, MediaType: "movie"}}
	for i := 0; i < 2; i++ {
		statuses, err := client.AvailabilityBatch(context.Background(), items)
		if err != nil {
			t.Fatalf("AvailabilityBatch: %v", err)
		}
		if statuses["movie:603"] != "processing" || statuses["tv:1399"] != "partial" || statuses["movie:999"] != "unknown" {
			t.Fatalf("statuts = %v", statuses)
		}
	}
	if fake.count("GET /movie/603?language=fr-FR") != 1 || fake.count("GET /tv/1399") != 1 {
		t.Fatalf("une fiche relue dans la demi-minute : %v", fake.seen())
	}
}

func TestSeerrBatchSaysAMuteAddress(t *testing.T) {
	client, _ := newFakeSeerr(t, ServiceJellyseerr, nil)
	client.BaseURL = "http://127.0.0.1:1"
	_, err := client.AvailabilityBatch(context.Background(), []BatchItem{{TMDBID: 603, MediaType: "movie"}})
	if !IsUnreachable(err) {
		t.Fatalf("erreur = %v", err)
	}
}

func TestSeerrFeedLeavesOutTheReadersOwnAndStartsAtTheNewest(t *testing.T) {
	client, _ := newFakeSeerr(t, ServiceJellyseerr, nil)
	admin := Account{ID: 1, Username: "admin"}

	// Sans curseur : seulement où en est le flux.
	start, err := client.Feed(context.Background(), admin, nil)
	if err != nil || start.Cursor != 14 || len(start.Requests) != 0 {
		t.Fatalf("départ = %+v (%v)", start, err)
	}

	after := 11
	feed, err := client.Feed(context.Background(), admin, &after)
	if err != nil {
		t.Fatalf("Feed: %v", err)
	}
	if feed.Cursor != 14 || len(feed.Requests) != 3 || feed.Requests[0].ID != 12 || feed.Requests[2].ID != 14 ||
		feed.Requests[1].Title != "Game of Thrones" || len(feed.Requests[1].Seasons) != 2 || feed.Requests[1].Requester != "Lea" {
		t.Fatalf("flux = %+v", feed)
	}

	// hugo ne se notifie pas de sa propre demande (la 14).
	own, err := client.Feed(context.Background(), Account{ID: 8, Username: "hugo"}, &after)
	if err != nil || len(own.Requests) != 2 || own.Cursor != 14 {
		t.Fatalf("flux de hugo = %+v (%v)", own, err)
	}
}

func TestSeerrModerationCallsTheDecisionForEachRequest(t *testing.T) {
	client, fake := newFakeSeerr(t, ServiceJellyseerr, map[string]http.HandlerFunc{
		"POST /request/14/approve": func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte(`{}`)) },
		"POST /request/14/decline": func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusConflict)
			_, _ = w.Write([]byte(`{"message":"Only pending requests can be approved or declined."}`))
		},
		"DELETE /request/14": func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) },
	})
	admin := Account{ID: 1, Username: "admin"}
	if err := client.Moderate(context.Background(), admin, []int{14}, ActionApprove, ""); err != nil {
		t.Fatalf("approve: %v", err)
	}
	if err := client.Moderate(context.Background(), admin, []int{14}, ActionDelete, ""); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if fake.count("POST /request/14/approve as=1") != 1 || fake.count("DELETE /request/14 as=1") != 1 {
		t.Fatalf("appels = %v", fake.seen())
	}
	// Le refus de Seerr remonte avec son statut, dans la forme que l'app lit.
	err := client.Moderate(context.Background(), admin, []int{14}, ActionDecline, "Doublon")
	var refused *StatusError
	if !errors.As(err, &refused) || refused.Status != http.StatusConflict || !json.Valid(refused.Body) ||
		!strings.Contains(string(refused.Body), "Seule une demande en attente") {
		t.Fatalf("refus = %v", err)
	}
}

func TestSeerrLotWithAnAlreadyDecidedRequestStillTakesTheDecision(t *testing.T) {
	// Le même film redemandé après un refus : le lot porte les deux demandes,
	// et Seerr ne décide que celle qui attend.
	client, fake := newFakeSeerr(t, ServiceJellyseerr, map[string]http.HandlerFunc{
		"POST /request/15/approve": func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte(`{}`)) },
		"POST /request/11/approve": func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusConflict)
			_, _ = w.Write([]byte(`{"message":"Only pending requests can be approved or declined."}`))
		},
	})
	admin := Account{ID: 1, Username: "admin"}
	if err := client.Moderate(context.Background(), admin, []int{15, 11}, ActionApprove, ""); err != nil {
		t.Fatalf("lot mêlé : %v", err)
	}
	if fake.count("POST /request/15/approve") != 1 || fake.count("POST /request/11/approve") != 1 {
		t.Fatalf("appels = %v", fake.seen())
	}
	// Seule, la demande déjà décidée dit pourquoi rien ne s'est passé.
	if err := client.Moderate(context.Background(), admin, []int{11}, ActionApprove, ""); err == nil {
		t.Fatal("une demande déjà décidée a été dite approuvée")
	}
}

func TestSeerrContractProgressComesFromTheDownloadQueue(t *testing.T) {
	client, _ := newFakeSeerr(t, ServiceJellyseerr, nil)
	progress, err := client.Progress(context.Background(), Account{Username: "lea"}, 603, "movie")
	if err != nil {
		t.Fatalf("Progress: %v", err)
	}
	download := progress.Download
	if !progress.Active || !progress.Downloading || download == nil || download.Progress != 75 ||
		*download.Size != "8.0 GB" || *download.SizeLeft != "2.0 GB" || *download.TimeLeft != "12m" ||
		*download.ReleaseTitle != "The.Matrix.1999.1080p.BluRay" || progress.Imports == nil {
		t.Fatalf("suivi = %+v, %+v", progress, download)
	}

	idle, err := client.Progress(context.Background(), Account{Username: "lea"}, 1399, "tv")
	if err != nil || idle.Active || idle.Download != nil || idle.Imports == nil {
		t.Fatalf("rien en cours = %+v (%v)", idle, err)
	}
}

func TestSeerrTimeLeftIsShortenedLikeMediaHubs(t *testing.T) {
	cases := map[string]string{
		"":            "",
		"00:12:34":    "12m",
		"01:05:09":    "1h05",
		"00:00:40":    "<1m",
		"1.02:03:04":  "26h03",
		"bientôt":     "bientôt",
		"12:34":       "12:34",
		"aa:bb:cc":    "aa:bb:cc",
		" 00:02:00  ": "2m",
	}
	for raw, want := range cases {
		if got := seerrTimeLeft(raw); got != want {
			t.Errorf("seerrTimeLeft(%q) = %q, attendu %q", raw, got, want)
		}
	}
}

func TestSeerrForgetRemovesAWholeTitleFromTheManagerThenItsRequests(t *testing.T) {
	routes := map[string]http.HandlerFunc{
		"DELETE /media/29/file": func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) },
		"DELETE /media/29":      func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) },
		"DELETE /media/30":      func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) },
	}
	client, fake := newFakeSeerr(t, ServiceJellyseerr, routes)
	admin := Account{ID: 1, Username: "admin"}

	removal, err := client.ForgetMedia(context.Background(), admin, 603, "movie", nil)
	if err != nil || removal != (Removal{Manager: "arr", ManagerRemoved: true, RequestsRemoved: 1}) {
		t.Fatalf("film = %+v (%v)", removal, err)
	}
	calls := fake.seen()
	file, media := -1, -1
	for i, call := range calls {
		switch call {
		case "DELETE /media/29/file as=1":
			file = i
		case "DELETE /media/29 as=1":
			media = i
		}
	}
	if file < 0 || media < file {
		t.Fatalf("ordre des retraits : %v", calls)
	}

	// Un Overseerr sans la route des fichiers (404) : la fiche part quand même.
	removal, err = client.ForgetMedia(context.Background(), admin, 1399, "tv", nil)
	if err != nil || removal.ManagerRemoved || removal.RequestsRemoved != 2 {
		t.Fatalf("série = %+v (%v)", removal, err)
	}

	// Une saison seule ne se retire pas chez Seerr : rien n'y bouge.
	before := len(fake.seen())
	season := 2
	removal, err = client.ForgetMedia(context.Background(), admin, 1399, "tv", &season)
	if err != nil || removal != (Removal{Manager: "arr"}) || len(fake.seen()) != before {
		t.Fatalf("saison = %+v (%v), appels %v", removal, err, fake.seen()[before:])
	}

	// Un titre que Seerr ne suit pas : ni gestionnaire ni demandes à prévenir.
	removal, err = client.ForgetMedia(context.Background(), admin, 999, "movie", nil)
	if err != nil || removal != (Removal{Manager: "arr"}) {
		t.Fatalf("titre inconnu = %+v (%v)", removal, err)
	}
}

func TestSeerrHasNoInteractiveSearch(t *testing.T) {
	client, _ := newFakeSeerr(t, ServiceOverseerr, nil)
	if _, err := client.Releases(context.Background(), Account{Username: "admin"}, ReleaseTarget{TMDBID: 603, MediaType: "movie"}); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("Releases = %v", err)
	}
}

func TestProbeSeerrTellsTheAddressFromTheKey(t *testing.T) {
	client, _ := newFakeSeerr(t, ServiceJellyseerr, nil)
	link, err := client.ProbeSeerr(context.Background(), Account{Username: "lea"})
	if err != nil || !link.Answered || !link.KeyAccepted || link.Version != "2.7.3" || !link.Linked || link.KeyAccount != "admin" {
		t.Fatalf("liaison = %+v (%v)", link, err)
	}

	stranger, err := client.ProbeSeerr(context.Background(), Account{Username: "inconnue"})
	if err != nil || !stranger.KeyAccepted || stranger.Linked {
		t.Fatalf("compte sans homonyme = %+v (%v)", stranger, err)
	}

	client.APIKey = "autre"
	refused, err := client.ProbeSeerr(context.Background(), Account{Username: "lea"})
	if err != nil || !refused.Answered || refused.KeyAccepted {
		t.Fatalf("clé refusée = %+v (%v)", refused, err)
	}

	// Une adresse qui répond autre chose (ici un MediaHub) n'est pas un Seerr.
	other := httptest.NewServer(http.NotFoundHandler())
	t.Cleanup(other.Close)
	client.BaseURL = other.URL
	if link, err := client.ProbeSeerr(context.Background(), Account{}); err != nil || link.Answered {
		t.Fatalf("pas un Seerr = %+v (%v)", link, err)
	}

	client.BaseURL = "http://127.0.0.1:1"
	if _, err := client.ProbeSeerr(context.Background(), Account{}); !IsUnreachable(err) {
		t.Fatalf("adresse muette = %v", err)
	}
}
