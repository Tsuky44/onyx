package mediahub

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"sync"

	"project-player/server/safego"
)

// Les demandes chez Seerr (ADR-0136). Une demande y couvre un film ou
// plusieurs saisons d'une série, sans titre ni affiche : Onyx la remet en
// lignes de MediaHub (une par état), y pose le titre lu sur la fiche, et
// GroupLots en fait les mêmes lots que pour MediaHub.

type seerrSeasonRequest struct {
	SeasonNumber int `json:"seasonNumber"`
	Status       int `json:"status"`
}

type seerrRequest struct {
	ID          int                  `json:"id"`
	Status      int                  `json:"status"`
	CreatedAt   string               `json:"createdAt"`
	UpdatedAt   string               `json:"updatedAt"`
	Type        string               `json:"type"`
	Is4k        bool                 `json:"is4k"`
	Media       *seerrMedia          `json:"media"`
	Seasons     []seerrSeasonRequest `json:"seasons"`
	RequestedBy *seerrUser           `json:"requestedBy"`
}

func (r seerrRequest) tmdbID() int {
	if r.Media == nil {
		return 0
	}
	return r.Media.TMDBID
}

func (r seerrRequest) requester() string {
	if r.RequestedBy == nil {
		return ""
	}
	return r.RequestedBy.name()
}

type seerrRequestList struct {
	PageInfo struct {
		Results int `json:"results"`
	} `json:"pageInfo"`
	Results []seerrRequest `json:"results"`
}

// seerrRequestStatus traduit une demande d'après sa décision et ce que le
// titre (ou la saison) est devenu : Overseerr laisse « approuvée » une
// demande dont le titre est arrivé, c'est l'état du titre qui le dit.
func seerrRequestStatus(request, media int) string {
	switch request {
	case seerrRequestPending:
		return "pending"
	case seerrRequestDeclined:
		return "declined"
	case seerrRequestCompleted:
		return "available"
	}
	switch media {
	case seerrMediaAvailable:
		return "available"
	case seerrMediaPartial:
		return "partial"
	case seerrMediaProcessing:
		return "processing"
	default:
		// Approuvée, pas encore prise par Radarr ou Sonarr (ou échouée chez
		// Jellyseerr) : MediaHub dit « approved » du même entre-deux.
		return "approved"
	}
}

// seerrSeasonRequestStatus dit où en est une saison demandée. La décision est
// celle de la demande ; l'arrivée est celle de la saison quand Seerr la
// connaît, sinon celle de la série, où « en partie » ne dit pas laquelle.
func seerrSeasonRequestStatus(request seerrRequest, season seerrSeasonRequest) string {
	decision := request.Status
	if decision != seerrRequestPending && decision != seerrRequestDeclined && season.Status != 0 {
		decision = season.Status
	}
	held := request.Media.seasonStatus(season.SeasonNumber, request.Is4k)
	if held != seerrMediaAvailable && held != seerrMediaPartial {
		held = request.Media.status(request.Is4k)
		if held == seerrMediaPartial {
			held = seerrMediaProcessing
		}
	}
	return seerrRequestStatus(decision, held)
}

// seerrRows remet les demandes de Seerr en lignes de MediaHub. Les saisons
// d'une demande qui en sont au même point font une ligne.
func seerrRows(requests []seerrRequest, titles map[string]seerrTitle) []Request {
	rows := make([]Request, 0, len(requests))
	for _, request := range requests {
		tmdbID := request.tmdbID()
		if tmdbID <= 0 || (request.Type != "movie" && request.Type != "tv") {
			continue
		}
		title := titles[AvailabilityKey(request.Type, tmdbID)]
		if title.Title == "" {
			// La fiche n'a pas répondu : la demande se montre quand même.
			title.Title = "TMDB " + strconv.Itoa(tmdbID)
		}
		base := Request{
			ID:          request.ID,
			MediaType:   request.Type,
			TMDBID:      tmdbID,
			Title:       title.Title,
			PosterPath:  title.PosterPath,
			Seasons:     []int{},
			RequestedAt: request.CreatedAt,
			UpdatedAt:   request.UpdatedAt,
			Progress:    seerrDownloadPercent(request.Media.downloads(request.Is4k)),
			Requester:   request.requester(),
		}
		if request.Type == "movie" || len(request.Seasons) == 0 {
			base.Status = seerrRequestStatus(request.Status, request.Media.status(request.Is4k))
			rows = append(rows, base)
			continue
		}
		var order []string
		byStatus := map[string][]int{}
		for _, season := range request.Seasons {
			status := seerrSeasonRequestStatus(request, season)
			if _, ok := byStatus[status]; !ok {
				order = append(order, status)
			}
			byStatus[status] = append(byStatus[status], season.SeasonNumber)
		}
		for _, status := range order {
			row := base
			row.Status, row.Seasons = status, byStatus[status]
			rows = append(rows, row)
		}
	}
	return rows
}

// seerrFillTitles lit, quelques fiches à la fois, ce qui manque aux demandes :
// le titre et l'affiche, que Seerr ne garde pas, et l'état des saisons d'une
// série arrivée en partie, que sa liste de demandes ne donne pas.
func (c Client) seerrFillTitles(ctx context.Context, requests []seerrRequest) map[string]seerrTitle {
	titles := map[string]seerrTitle{}
	type target struct {
		mediaType string
		tmdbID    int
	}
	var missing []target
	seen := map[string]bool{}
	for _, request := range requests {
		tmdbID := request.tmdbID()
		key := AvailabilityKey(request.Type, tmdbID)
		if tmdbID <= 0 || seen[key] {
			continue
		}
		seen[key] = true
		partial := request.Type == "tv" && request.Media.status(request.Is4k) == seerrMediaPartial
		if title, ok := seerrTitles.Get(c.seerrTitleKey(request.Type, tmdbID)); ok && !partial {
			titles[key] = title
			continue
		}
		missing = append(missing, target{request.Type, tmdbID})
	}

	var (
		mu      sync.Mutex
		wg      sync.WaitGroup
		slots   = make(chan struct{}, seerrFanOut)
		seasons = map[string][]seerrSeason{}
	)
	for _, want := range missing {
		wg.Add(1)
		go func(want target) {
			defer safego.Recover("mediahub/seerr_requests.go: titles")
			defer wg.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			details, err := c.seerrDetails(ctx, want.mediaType, want.tmdbID, false)
			if err != nil {
				// La demande garde son numéro TMDB pour titre.
				return
			}
			key := AvailabilityKey(want.mediaType, want.tmdbID)
			title := details.Title
			if title == "" {
				title = details.Name
			}
			mu.Lock()
			defer mu.Unlock()
			titles[key] = seerrTitle{Title: title, PosterPath: details.PosterPath}
			if details.MediaInfo != nil {
				seasons[key] = details.MediaInfo.Seasons
			}
		}(want)
	}
	wg.Wait()

	for i := range requests {
		media := requests[i].Media
		if media == nil || len(media.Seasons) > 0 {
			continue
		}
		media.Seasons = seasons[AvailabilityKey(requests[i].Type, media.TMDBID)]
	}
	return titles
}

// seerrList lit les demandes les plus récentes, au nom du compte Seerr actAs.
// requestedBy > 0 ne garde que celles de ce compte.
func (c Client) seerrList(ctx context.Context, actAs, requestedBy, pages int) ([]seerrRequest, error) {
	query := url.Values{
		"take":   {strconv.Itoa(requestPageSize)},
		"sort":   {"added"},
		"filter": {"all"},
	}
	if requestedBy > 0 {
		query.Set("requestedBy", strconv.Itoa(requestedBy))
	}
	var requests []seerrRequest
	for page := 0; page < pages; page++ {
		query.Set("skip", strconv.Itoa(page*requestPageSize))
		raw, err := c.seerr(ctx, http.MethodGet, "/request", actAs, query, nil)
		if err != nil {
			return nil, err
		}
		var list seerrRequestList
		if err := json.Unmarshal(raw, &list); err != nil {
			return nil, fmt.Errorf("mediahub: decode seerr requests: %w", err)
		}
		requests = append(requests, list.Results...)
		if len(list.Results) < requestPageSize || len(requests) >= list.PageInfo.Results {
			break
		}
	}
	return requests, nil
}

// seerrRequests rend les demandes en lots. Seerr juge du droit de lire celles
// des autres : sans lui, « toutes » ne rend que celles du compte.
func (c Client) seerrRequests(ctx context.Context, as Account, scope Scope) ([]Lot, error) {
	identity, err := c.seerrIdentity(ctx, as)
	if err != nil {
		return nil, err
	}
	requestedBy := 0
	if scope == ScopeMine {
		requestedBy = identity.user.ID
	}
	requests, err := c.seerrList(ctx, identity.user.ID, requestedBy, requestPages)
	if err != nil {
		return nil, err
	}
	return GroupLots(seerrRows(requests, c.seerrFillTitles(ctx, requests))), nil
}

// seerrFeed rend les demandes faites depuis after par les autres comptes, les
// plus anciennes d'abord. Le curseur est le plus grand numéro de demande :
// Seerr les numérote dans l'ordre.
func (c Client) seerrFeed(ctx context.Context, as Account, after *int) (Feed, error) {
	identity, err := c.seerrIdentity(ctx, as)
	if err != nil {
		return Feed{}, err
	}
	requests, err := c.seerrList(ctx, identity.user.ID, 0, 1)
	if err != nil {
		return Feed{}, err
	}
	feed := Feed{Requests: []FeedEntry{}}
	if after != nil {
		feed.Cursor = *after
	}
	var fresh []seerrRequest
	for _, request := range requests {
		if request.ID > feed.Cursor {
			feed.Cursor = request.ID
		}
		if after == nil || request.ID <= *after {
			continue
		}
		if request.RequestedBy != nil && request.RequestedBy.ID == identity.user.ID {
			continue
		}
		fresh = append(fresh, request)
	}
	if len(fresh) == 0 {
		return feed, nil
	}
	titles := c.seerrFillTitles(ctx, fresh)
	for i := len(fresh) - 1; i >= 0; i-- {
		request := fresh[i]
		tmdbID := request.tmdbID()
		if tmdbID <= 0 {
			continue
		}
		title := titles[AvailabilityKey(request.Type, tmdbID)]
		if title.Title == "" {
			title.Title = "TMDB " + strconv.Itoa(tmdbID)
		}
		seasons := []int{}
		for _, season := range request.Seasons {
			seasons = append(seasons, season.SeasonNumber)
		}
		feed.Requests = append(feed.Requests, FeedEntry{
			ID:          request.ID,
			MediaType:   request.Type,
			TMDBID:      tmdbID,
			Title:       title.Title,
			PosterPath:  title.PosterPath,
			Seasons:     seasons,
			Requester:   request.requester(),
			RequestedAt: request.CreatedAt,
		})
	}
	return feed, nil
}

// seerrCreate traduit la demande de l'app pour Seerr et l'envoie au nom du
// compte : Seerr applique ses droits, ses quotas et son approbation
// automatique. Sans saisons, une série se demande entière.
func (c Client) seerrCreate(ctx context.Context, as Account, body []byte) (int, []byte, error) {
	var asked struct {
		TMDBID    int    `json:"tmdbId"`
		MediaType string `json:"mediaType"`
		Seasons   []int  `json:"seasons"`
	}
	if err := json.Unmarshal(body, &asked); err != nil || asked.TMDBID <= 0 ||
		(asked.MediaType != "movie" && asked.MediaType != "tv") {
		return 0, nil, &StatusError{Status: http.StatusBadRequest, Body: []byte(`{"error":"Demande invalide."}`)}
	}
	identity, err := c.seerrIdentity(ctx, as)
	if err != nil {
		return 0, nil, err
	}
	request := map[string]any{"mediaType": asked.MediaType, "mediaId": asked.TMDBID}
	if asked.MediaType == "tv" {
		if len(asked.Seasons) > 0 {
			request["seasons"] = asked.Seasons
		} else {
			request["seasons"] = "all"
		}
	}
	payload, err := json.Marshal(request)
	if err != nil {
		return 0, nil, fmt.Errorf("mediahub: encode seerr request: %w", err)
	}

	header := http.Header{}
	header.Set("X-Api-Key", c.key())
	header.Set("X-Api-User", strconv.Itoa(identity.user.ID))
	status, raw, err := c.roundTrip(ctx, http.MethodPost, SeerrPath+"/request", header, nil, payload)
	if err != nil {
		return 0, nil, err
	}
	c.forgetSeerrDetails(asked.MediaType, asked.TMDBID)
	switch {
	case status == http.StatusAccepted:
		// Seerr répond 202 quand il ne reste aucune saison à demander.
		return http.StatusConflict, []byte(`{"error":"Ces saisons sont déjà demandées ou disponibles."}`), nil
	case status < 200 || status > 299:
		failure := c.seerrFailure(status, raw)
		return failure.Status, failure.Body, nil
	}
	return http.StatusCreated, []byte(`{"success":true,"created":true}`), nil
}

// seerrModerate applique la décision à chaque demande, au nom du compte :
// Seerr juge du droit. Il ne garde pas de motif de refus.
//
// Un lot peut mêler une demande en attente et une plus ancienne déjà décidée
// (le même titre redemandé après un refus) : Seerr répond 409 pour celle-ci.
// Ce n'est un échec que si aucune demande du lot n'a pris la décision.
func (c Client) seerrModerate(ctx context.Context, as Account, ids []int, action Action) error {
	identity, err := c.seerrIdentity(ctx, as)
	if err != nil {
		return err
	}
	decided := 0
	var alreadyDecided error
	for _, id := range ids {
		method, path := http.MethodPost, "/request/"+strconv.Itoa(id)+"/"+string(action)
		if action == ActionDelete {
			method, path = http.MethodDelete, "/request/"+strconv.Itoa(id)
		}
		_, err := c.seerr(ctx, method, path, identity.user.ID, nil, nil)
		var refused *StatusError
		if action != ActionDelete && errors.As(err, &refused) && refused.Status == http.StatusConflict {
			alreadyDecided = err
			continue
		}
		if err != nil {
			return err
		}
		decided++
	}
	if decided == 0 {
		return alreadyDecided
	}
	return nil
}
