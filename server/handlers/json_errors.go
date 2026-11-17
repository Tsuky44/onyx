package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"project-player/server/i18n"
)

// writeJSONError répond une erreur sous la seule forme que l'app sait lire :
// {"error": "…"}, avec un Content-Type JSON.
//
// Une centaine de routes passaient par http.Error avec un littéral JSON : le
// corps avait la bonne allure, mais l'en-tête disait text/plain. Dio ne
// décode alors pas la réponse, et l'app affichait « Une erreur est survenue »
// au lieu du message du serveur. Toutes les erreurs JSON passent par ici.
//
// message est la phrase en français, traduite dans la langue de la requête
// (ADR-0137) ; les valeurs variables s'y écrivent {0}, {1}… et se passent en
// args. Une erreur technique d'un service externe se passe aussi en argument :
// elle reste brute, derrière une phrase traduite.
func writeJSONError(w http.ResponseWriter, status int, message string, args ...any) {
	text := i18n.Respond(w, message, args...)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": text})
}

// writeJSONFailure répond l'erreur d'un service ou d'un validateur. Une
// i18n.Error se traduit comme un message écrit sur place ; toute autre erreur
// vient d'un système qu'Onyx ne contrôle pas : son texte reste brut, derrière
// une phrase traduite.
func writeJSONFailure(w http.ResponseWriter, status int, err error) {
	var msg *i18n.Error
	if errors.As(err, &msg) {
		writeJSONError(w, status, msg.Key, msg.Args...)
		return
	}
	writeJSONError(w, status, "Erreur : {0}", err.Error())
}
