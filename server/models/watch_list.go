package models

import "time"

// Les listes d'un compte : « à regarder plus tard » et les siennes, partagées
// ou non avec les autres comptes du serveur. Voir ADR-0070.

const (
	// WatchListKindWatchLater est la liste que chaque compte a d'office. Elle
	// ne se renomme ni ne se supprime ; l'app l'affiche sous son nom traduit.
	WatchListKindWatchLater = "watch_later"
	// WatchListKindCustom est une liste faite par le compte.
	WatchListKindCustom = "custom"
)

// WatchListOwner est le compte à qui appartient une liste.
type WatchListOwner struct {
	ID       int    `json:"id"`
	Username string `json:"username"`
}

// WatchList est le résumé d'une liste : ce que montrent la page des listes et
// la feuille « Ajouter à une liste ».
type WatchList struct {
	ID          int    `json:"id"`
	Kind        string `json:"kind"`
	Name        string `json:"name"`
	Description string `json:"description"`
	IsShared    bool   `json:"is_shared"`
	IsMine      bool   `json:"is_mine"`
	// CanEdit : le compte qui lit peut y ajouter et en retirer des titres,
	// parce qu'elle est à lui ou que son propriétaire l'y a invité à la
	// remplir (ADR-0127, ADR-0129).
	CanEdit bool `json:"can_edit"`
	// IsMember : le compte qui lit y est invité, pour la remplir ou seulement
	// pour la voir ; il peut la quitter (ADR-0129).
	IsMember bool `json:"is_member"`
	// MemberCount est le nombre de comptes invités, qu'ils la remplissent ou
	// qu'ils la voient seulement.
	MemberCount int            `json:"member_count"`
	Owner       WatchListOwner `json:"owner"`
	ItemCount   int            `json:"item_count"`
	// Posters sont les affiches des derniers ajouts, quatre au plus, pour la
	// vignette de la liste.
	Posters   []string  `json:"posters"`
	UpdatedAt time.Time `json:"updated_at"`
	// ContainsItemID est l'élément de cette liste qui porte le titre demandé
	// par ?media_id= ou ?tmdb_id= (0 s'il n'y est pas). Absent sans question.
	ContainsItemID *int `json:"contains_item_id,omitempty"`
	// WatchedCount est le nombre de titres de la liste que le compte qui lit
	// a vus, parmi ceux que le serveur a ; OnServerCount, combien de titres
	// le serveur a (ItemCount - OnServerCount restent à demander). Voir
	// ADR-0159.
	WatchedCount  int `json:"watched_count"`
	OnServerCount int `json:"on_server_count"`
	// NextItem est le premier titre du serveur que le compte n'a pas vu, dans
	// l'ordre d'ajout ; absent quand il a tout vu ou que le serveur n'a rien.
	NextItem *WatchListNext `json:"next_item,omitempty"`
}

// WatchListNext est le prochain titre à regarder d'une liste : de quoi
// l'afficher et le lancer, sans la fiche complète (ADR-0159).
type WatchListNext struct {
	ID          int    `json:"id"`
	MediaID     int    `json:"media_id"`
	MediaType   string `json:"media_type"`
	Title       string `json:"title"`
	PosterURL   string `json:"poster_url"`
	ReleaseDate string `json:"release_date"`
}

// WatchListItem est un film ou une série d'une liste, sur le serveur ou pas.
type WatchListItem struct {
	ID          int       `json:"id"`
	MediaType   string    `json:"media_type"`
	TMDBID      int       `json:"tmdb_id"`
	Title       string    `json:"title"`
	PosterURL   string    `json:"poster_url"`
	ReleaseDate string    `json:"release_date"`
	AddedAt     time.Time `json:"added_at"`
	// MediaID est la fiche du serveur à laquelle l'élément se rattache, 0
	// quand le serveur n'a pas (ou plus) ce titre.
	MediaID int `json:"media_id"`
	// Watched : le compte qui lit a vu ce titre (un film terminé, une série dont
	// chaque épisode présent l'est). Toujours faux pour un titre que le serveur
	// n'a pas. Rempli par le détail d'une liste seulement (ADR-0159).
	Watched bool `json:"watched"`
	// EpisodesWatched et EpisodesTotal disent où le compte en est d'une série :
	// combien de ses épisodes présents sur le disque il a terminés, sur combien.
	// NextEpisodeSeason et NextEpisodeNumber nomment le premier qu'il lui reste à
	// voir (0 quand il a tout vu). Absents pour un film et pour une série que le
	// serveur n'a pas ; remplis par le détail d'une liste seulement.
	EpisodesWatched   int `json:"episodes_watched,omitempty"`
	EpisodesTotal     int `json:"episodes_total,omitempty"`
	NextEpisodeSeason int `json:"next_episode_season,omitempty"`
	NextEpisodeNumber int `json:"next_episode_number,omitempty"`
	// Media est cette fiche, avec la progression du compte qui lit la liste.
	Media *HomeMediaItem `json:"media,omitempty"`
}

// Ce qu'un invité peut faire d'une liste (ADR-0129).
const (
	// WatchListRoleEditor : il y ajoute et en retire des titres.
	WatchListRoleEditor = "editor"
	// WatchListRoleViewer : il la voit, même privée, sans la modifier.
	WatchListRoleViewer = "viewer"
)

// WatchListMember est un compte du serveur, tel qu'une liste le montre : ses
// invités, et ceux qu'on peut inviter.
type WatchListMember struct {
	ID       int    `json:"id"`
	Username string `json:"username"`
	Avatar   string `json:"avatar"`
	// Role est WatchListRoleEditor ou WatchListRoleViewer pour un invité ;
	// absent pour un compte qu'on peut inviter.
	Role string `json:"role,omitempty"`
}

// WatchListDetail est une liste et son contenu, du plus récent ajout au plus
// ancien, avec les comptes invités à la modifier.
type WatchListDetail struct {
	WatchList
	Items   []WatchListItem   `json:"items"`
	Members []WatchListMember `json:"members"`
}

// WatchListsResponse range les listes du compte et celles que les autres
// partagent.
type WatchListsResponse struct {
	Mine   []WatchList `json:"mine"`
	Shared []WatchList `json:"shared"`
}
