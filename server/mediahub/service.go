package mediahub

import "strings"

// Service est le compagnon de demandes réglé dans Onyx (ADR-0136). MediaHub
// parle son API d'intégration (ou celle d'OnyxHub, reconnue par sonde) ;
// Overseerr et Jellyseerr partagent une même API, celle de Seerr.
type Service string

const (
	ServiceMediaHub   Service = "mediahub"
	ServiceOverseerr  Service = "overseerr"
	ServiceJellyseerr Service = "jellyseerr"
)

// ParseService lit un réglage. Vide vaut MediaHub : c'est ce qu'avait une
// installation d'avant le choix du service.
func ParseService(raw string) (Service, bool) {
	switch service := Service(strings.ToLower(strings.TrimSpace(raw))); service {
	case "":
		return ServiceMediaHub, true
	case ServiceMediaHub, ServiceOverseerr, ServiceJellyseerr:
		return service, true
	default:
		return ServiceMediaHub, false
	}
}

// Seerr dit si le service parle l'API d'Overseerr et de Jellyseerr.
func (s Service) Seerr() bool { return s == ServiceOverseerr || s == ServiceJellyseerr }

// Label est le nom du service tel qu'un message le montre.
func (s Service) Label() string {
	switch s {
	case ServiceOverseerr:
		return "Overseerr"
	case ServiceJellyseerr:
		return "Jellyseerr"
	default:
		return "MediaHub"
	}
}
