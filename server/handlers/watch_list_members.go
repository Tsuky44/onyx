package handlers

import (
	"net/http"

	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// Les invités d'une liste (ADR-0127) : le propriétaire choisit les comptes qui
// peuvent y ajouter des titres. Les règles tiennent dans watchlists ; ici, on
// lit l'URL et on traduit les erreurs, avec writeWatchListError.

// ListWatchListPeople renvoie les autres comptes du serveur, ceux qu'on peut
// inviter (GET /api/list-people).
func ListWatchListPeople(w http.ResponseWriter, _ *http.Request, _ httprouter.Params, userID int) {
	people, err := watchListStore().People(userID)
	if err != nil {
		writeWatchListError(w, "ListWatchListPeople", err)
		return
	}
	writeWatchListJSON(w, http.StatusOK, people)
}

// AddWatchListMember invite un compte à remplir une liste du compte
// (PUT /api/lists/:id/members/:user). Inviter deux fois renvoie les mêmes
// invités. La réponse est la liste des invités.
func AddWatchListMember(w http.ResponseWriter, _ *http.Request, ps httprouter.Params, userID int) {
	listID, ok := listIDParam(w, ps, "id")
	if !ok {
		return
	}
	memberID, ok := listIDParam(w, ps, "user")
	if !ok {
		return
	}
	members, err := watchListStore().AddMember(userID, listID, memberID)
	if err != nil {
		writeWatchListError(w, "AddWatchListMember", err)
		return
	}
	writeWatchListJSON(w, http.StatusOK, membersOrEmpty(members))
}

// RemoveWatchListMember retire un invité d'une liste, ou fait quitter la liste
// à l'invité qui se retire lui-même (DELETE /api/lists/:id/members/:user).
func RemoveWatchListMember(w http.ResponseWriter, _ *http.Request, ps httprouter.Params, userID int) {
	listID, ok := listIDParam(w, ps, "id")
	if !ok {
		return
	}
	memberID, ok := listIDParam(w, ps, "user")
	if !ok {
		return
	}
	if err := watchListStore().RemoveMember(userID, listID, memberID); err != nil {
		writeWatchListError(w, "RemoveWatchListMember", err)
		return
	}
	writeWatchListJSON(w, http.StatusOK, statusResponse{Status: "ok"})
}

// membersOrEmpty évite le « null » JSON d'une liste d'invités vide.
func membersOrEmpty(m []models.WatchListMember) []models.WatchListMember {
	if m == nil {
		return []models.WatchListMember{}
	}
	return m
}
