package i18n

import (
	"net/http"
	"strings"
)

// Middleware pose sur la réponse la langue que la requête a demandée
// (Content-Language), pour que les écrivains d'erreurs, qui n'ont que le
// ResponseWriter, sachent dans quelle langue répondre sans qu'on change la
// signature de leurs 550 appels. Content-Language dit exactement cela :
// la langue du corps qui suit.
//
// Seules les routes /api/ sont concernées : les médias et la SPA n'ont pas de
// message à traduire.
func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			w.Header().Set("Content-Language", FromRequest(r))
		}
		next.ServeHTTP(w, r)
	})
}

// FromWriter rend la langue que Middleware a posée sur la réponse, ou le
// français quand le handler n'est pas passé par lui (un test qui l'appelle
// directement, par exemple).
func FromWriter(w http.ResponseWriter) string {
	if code := w.Header().Get("Content-Language"); Supported(code) {
		return code
	}
	return Default
}

// Respond traduit un message pour la réponse w.
func Respond(w http.ResponseWriter, fr string, args ...any) string {
	return T(FromWriter(w), fr, args...)
}
