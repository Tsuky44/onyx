package webui

import (
	"net/http/httptest"
	"testing"
	"testing/fstest"
)

// Une autre page ne doit pas pouvoir afficher l'app dans un cadre.
func TestServeFileRefusesToBeFramed(t *testing.T) {
	h := &Handler{
		files: fstest.MapFS{"index.html": {Data: []byte("<html></html>")}},
		etags: map[string]string{"index.html": `"x"`},
	}
	rec := httptest.NewRecorder()
	if !h.serveFile(rec, httptest.NewRequest("GET", "/", nil), "index.html") {
		t.Fatal("index.html not served")
	}
	if got := rec.Header().Get("X-Frame-Options"); got != "DENY" {
		t.Errorf("X-Frame-Options = %q, want DENY", got)
	}
	if got := rec.Header().Get("Content-Security-Policy"); got == "" {
		t.Error("no Content-Security-Policy")
	}
}

// skwasm exige l'isolation inter-origines pour tourner en multi-thread ; sans
// ces deux en-tetes, crossOriginIsolated reste faux. Voir ADR-0147.
func TestServeFileIsCrossOriginIsolated(t *testing.T) {
	h := &Handler{
		files: fstest.MapFS{"index.html": {Data: []byte("<html></html>")}},
		etags: map[string]string{"index.html": `"x"`},
	}
	rec := httptest.NewRecorder()
	h.serveFile(rec, httptest.NewRequest("GET", "/", nil), "index.html")
	if got := rec.Header().Get("Cross-Origin-Opener-Policy"); got != "same-origin" {
		t.Errorf("COOP = %q, want same-origin", got)
	}
	if got := rec.Header().Get("Cross-Origin-Embedder-Policy"); got != "credentialless" {
		t.Errorf("COEP = %q, want credentialless", got)
	}
}

// Le chargeur WasmGC refuse un .wasm mal type et un .mjs qui n'est pas du JS.
func TestBundleContentTypeForWasmFiles(t *testing.T) {
	cases := map[string]string{
		"canvaskit/skwasm.wasm": "application/wasm",
		"canvaskit/skwasm.js":   "text/javascript; charset=utf-8",
		"main.dart.mjs":         "text/javascript; charset=utf-8",
		"main.dart.wasm":        "application/wasm",
		"index.html":            "text/html; charset=utf-8",
		"assets/blob.bin":       "application/octet-stream",
	}
	for name, want := range cases {
		if got := bundleContentType(name); got != want {
			t.Errorf("bundleContentType(%q) = %q, want %q", name, got, want)
		}
	}
}
