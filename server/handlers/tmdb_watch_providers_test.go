package handlers

import "testing"

func TestRankWatchProvidersPutsTheRegionsMostVisibleServicesFirst(t *testing.T) {
	movies := []tmdbWatchProvider{
		{ProviderID: 1, ProviderName: "ARTE VOD", DisplayPriorities: map[string]int{"FR": 40}},
		{ProviderID: 8, ProviderName: "Netflix", DisplayPriorities: map[string]int{"FR": 0, "US": 1}},
		{ProviderID: 9, ProviderName: "Amazon Prime Video", DisplayPriorities: map[string]int{"FR": 3}},
	}
	tv := []tmdbWatchProvider{
		// Disney+ meilleur en séries : il garde son meilleur rang.
		{ProviderID: 337, ProviderName: "Disney Plus", DisplayPriorities: map[string]int{"FR": 1}},
		{ProviderID: 8, ProviderName: "Netflix", DisplayPriorities: map[string]int{"FR": 2}},
		// Aucun rang pour la France : en fin de liste.
		{ProviderID: 77, ProviderName: "Apollo", DisplayPriorities: map[string]int{"US": 2}},
	}

	got := rankWatchProviders("FR", movies, tv)

	want := []string{"Netflix", "Disney Plus", "Amazon Prime Video", "ARTE VOD", "Apollo"}
	if len(got) != len(want) {
		t.Fatalf("got %d services, want %d (sans doublon)", len(got), len(want))
	}
	for i, name := range want {
		if got[i].ProviderName != name {
			t.Errorf("rang %d : got %q, want %q", i, got[i].ProviderName, name)
		}
	}
}

func TestRankWatchProvidersBreaksTiesByName(t *testing.T) {
	got := rankWatchProviders("FR", []tmdbWatchProvider{
		{ProviderID: 2, ProviderName: "Zeta"},
		{ProviderID: 1, ProviderName: "Alpha"},
	})
	if got[0].ProviderName != "Alpha" || got[1].ProviderName != "Zeta" {
		t.Fatalf("got %v, want Alpha puis Zeta", got)
	}
}
