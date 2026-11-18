# ADR-0147 — La version web passe en WebAssembly (skwasm), avec isolation inter-origines

- **Statut :** accepté. Build vérifié ; voir « Vérifications » pour ce qui l'a été dans le navigateur.
- **Date :** 2026-11-18
- **Portée :** `scripts/build-web.sh`, `scripts/build-web.ps1`, `server/webui/webui.go` (en-têtes et
  types MIME), `server/webui/webui_test.go`.
- **Complète** l'ADR-0076 (l'app web du serveur sert aussi les téléviseurs LG).

## Contexte

L'app web rendait avec CanvasKit en JavaScript : un seul thread pour l'interface et le rendu,
d'où des saccades. Flutter sait aussi compiler en WasmGC et rendre avec skwasm, qui déporte le
rendu dans un worker. Le projet ne pouvait pas le faire tant que `flutter_secure_storage_web`
dépendait de `dart:html` ; la version résolue (2.1.1) n'en dépend plus, et aucune autre
dépendance du lockfile n'importe `dart:html` ou `dart:js_util`. `flutter build web --wasm` compile.

skwasm n'est multi-thread que si la page est « cross-origin isolated » (`SharedArrayBuffer`), ce
qui exige les en-têtes COOP et COEP sur le document.

## Décision

1. **Les scripts de build passent `--wasm`.** Flutter produit alors le build WasmGC *et* le
   build JS de repli, et le chargeur choisit au démarrage selon la prise en charge de WasmGC.
   Les téléviseurs webOS et les navigateurs sans WasmGC gardent donc CanvasKit : le lanceur LG
   (ADR-0076) n'est pas touché. `skwasm*` et `wimp*` ne sont plus supprimés du bundle ; seul
   `experimental_webparagraph` l'est encore. La pré-compression gzip couvre aussi les `.mjs`.
2. **`webui.go` envoie `Cross-Origin-Opener-Policy: same-origin` et
   `Cross-Origin-Embedder-Policy: credentialless`** sur chaque fichier du bundle.
   `credentialless` plutôt que `require-corp` : les ressources d'un autre site chargées sans CORS
   (affiches TMDB, polices) se chargent sans exiger d'en-tête CORP de leur part, simplement sans
   cookies, ce dont elles n'ont pas besoin. Écartée : ne pas isoler la page — skwasm tournerait
   sur un seul thread et perdrait l'essentiel du gain.
3. **Les types MIME sont fixés dans le code** (`bundleContentType`) : `.wasm` →
   `application/wasm` (exigé par `compileStreaming`), `.js` et `.mjs` → `text/javascript`. On ne
   dépend plus de la table MIME du système.

## Conséquences

- Le bundle grossit des fichiers WasmGC (`main.dart.wasm`, `skwasm*.wasm`) ; le binaire Go
  les embarque. Le navigateur ne télécharge que la variante qu'il utilise.
- **COOP `same-origin` coupe `window.opener`** : une page ouverte par l'app ne peut plus la
  rejoindre. L'app ouvre ses liens externes avec `noopener` (`external_url_web.dart`) et le SSO
  MediaHub passe par un appel d'API (`/sso/redeem`), pas par un `postMessage` de popup : rien
  n'en dépend.
- **COEP `credentialless` et les autres serveurs Onyx** : un flux ou une API d'un *autre* serveur
  que celui qui a servi l'app est une ressource inter-origines. Les API répondent déjà
  `Access-Control-Allow-Origin: *` (`main.go`, `stream.go`, `subtitles.go`), ce qui suffit en
  mode CORS ; une balise `<video>` sans CORS le charge sans cookies, et le serveur n'en pose
  aucun.
- Un navigateur qui ne connaît pas `credentialless` (Safari, à notre connaissance — non vérifié)
  n'isole pas la page : skwasm tourne alors sans multi-thread, ou le chargeur prend le repli JS.
  Ce n'est pas une panne.
- Un navigateur lancé dans un iframe d'un autre site n'est de toute façon pas un cas : l'app
  refuse déjà d'être encadrée (`X-Frame-Options: DENY`).
- Tests : `TestServeFileIsCrossOriginIsolated`, `TestBundleContentTypeForWasmFiles`.
