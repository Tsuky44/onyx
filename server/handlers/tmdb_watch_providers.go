package handlers

import (
	"math"
	"sort"
)

// tmdbWatchProvider est une ligne de /watch/providers/{movie,tv} de TMDB.
// DisplayPriorities donne, par région, le rang d'affichage que TMDB attribue
// au service (0 = le plus en vue : Netflix, Prime Video… en France).
type tmdbWatchProvider struct {
	ProviderID        int            `json:"provider_id"`
	ProviderName      string         `json:"provider_name"`
	LogoPath          string         `json:"logo_path"`
	DisplayPriorities map[string]int `json:"display_priorities"`
	DisplayPriority   int            `json:"display_priority"`
}

// watchProviderRow est ce que l'app reçoit : le rang reste côté serveur,
// l'ordre de la liste le porte déjà.
type watchProviderRow struct {
	ProviderID   int    `json:"provider_id"`
	ProviderName string `json:"provider_name"`
	LogoPath     string `json:"logo_path"`
}

// rankWatchProviders fusionne les listes films et séries (sans doublon) et
// les range par rang d'affichage TMDB dans region, puis par nom. Avant, la
// liste était alphabétique : sur une centaine de services, Netflix et
// Disney+ arrivaient loin derrière « ARTE VOD » et « Action Max Amazon
// Channel ». Voir ADR-0132.
func rankWatchProviders(region string, lists ...[]tmdbWatchProvider) []watchProviderRow {
	type ranked struct {
		row  watchProviderRow
		rank int
	}
	byID := map[int]*ranked{}
	order := []int{}
	for _, list := range lists {
		for _, p := range list {
			rank := watchProviderRank(p, region)
			if seen, ok := byID[p.ProviderID]; ok {
				// Un service présent dans les deux listes garde son meilleur rang.
				if rank < seen.rank {
					seen.rank = rank
				}
				continue
			}
			byID[p.ProviderID] = &ranked{
				row: watchProviderRow{
					ProviderID:   p.ProviderID,
					ProviderName: p.ProviderName,
					LogoPath:     p.LogoPath,
				},
				rank: rank,
			}
			order = append(order, p.ProviderID)
		}
	}
	all := make([]ranked, 0, len(order))
	for _, id := range order {
		all = append(all, *byID[id])
	}
	sort.SliceStable(all, func(i, j int) bool {
		if all[i].rank != all[j].rank {
			return all[i].rank < all[j].rank
		}
		return all[i].row.ProviderName < all[j].row.ProviderName
	})
	out := make([]watchProviderRow, len(all))
	for i, r := range all {
		out[i] = r.row
	}
	return out
}

// watchProviderRank lit le rang du service dans region ; à défaut le rang
// global de TMDB, et en dernier recours la fin de la liste.
func watchProviderRank(p tmdbWatchProvider, region string) int {
	if rank, ok := p.DisplayPriorities[region]; ok {
		return rank
	}
	if p.DisplayPriorities == nil && p.DisplayPriority > 0 {
		return p.DisplayPriority
	}
	return math.MaxInt32
}
