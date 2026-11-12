package mediahub

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// Removal dit ce que MediaHub a oublié d'un titre qu'Onyx va supprimer du
// disque (ADR-0115) : Manager est « sorraa » ou « arr » (Radarr/Sonarr).
type Removal struct {
	Manager         string `json:"manager"`
	ManagerRemoved  bool   `json:"managerRemoved"`
	RequestsRemoved int    `json:"requestsRemoved"`
}

type removalBody struct {
	TMDBID    int    `json:"tmdbId"`
	MediaType string `json:"mediaType"`
	Season    *int   `json:"season,omitempty"`
}

// ForgetMedia demande à MediaHub de retirer le titre (ou la saison season)
// de son gestionnaire de téléchargement et d'en supprimer les demandes, sans
// toucher aux fichiers. mediaType est « movie » ou « tv ». OnyxHub n'a pas
// cette fonction : ErrUnsupported.
func (c Client) ForgetMedia(ctx context.Context, as Account, tmdbID int, mediaType string, season *int) (Removal, error) {
	dialect, err := c.dialect(ctx)
	if err != nil {
		return Removal{}, err
	}
	if dialect != DialectV1 {
		return Removal{}, ErrUnsupported
	}
	body, err := json.Marshal(removalBody{TMDBID: tmdbID, MediaType: mediaType, Season: season})
	if err != nil {
		return Removal{}, fmt.Errorf("mediahub: encode removal: %w", err)
	}
	raw, err := c.call(ctx, http.MethodPost, V1Path+"/library/removals", as, nil, body)
	if err != nil {
		return Removal{}, err
	}
	var removal Removal
	if err := json.Unmarshal(raw, &removal); err != nil {
		return Removal{}, fmt.Errorf("mediahub: decode removal: %w", err)
	}
	return removal, nil
}
