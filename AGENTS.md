# Standards d'Agents — Onyx

La source de vérité complète pour les standards d'ingénierie, l'architecture, la maintenabilité, le design multiplateforme, l'internationalisation, la sécurité et Graphify se trouve dans [`CLAUDE.md`](CLAUDE.md).

## Règles Transverses Fondamentales

1. **Communication & Fin de session** : Travail silencieux pendant la tâche (questions bloquantes uniquement). À la fin, récapitulatif structuré obligatoire : **Fait**, **Vérifié**, **Pas fait / Bloqué**, **À faire (Next Steps)**, **Décisions & ADRs**.
2. **Architecture Decision Records (ADRs)** : Consulter `docs/adr/` avant tout travail technique. Toute décision d'architecture, arbitrage ou nouveau pattern doit être documenté dans une nouvelle ADR (`docs/adr/00NN-titre-en-kebab.md`). Tout conflit avec une ADR existante doit être explicitement formulé.
3. **Internationalisation (i18n / l10n) 100% stricte** : Zéro texte en dur dans l'interface ou les erreurs serveur.
   - Flutter : `tr('clé_fr')` (ADR-0047), `trPlural()`, formats via `LocaleFormats`. Synchronisation immédiate dans `app/lib/l10n/en.dart`. Vérification par `flutter test test/l10n_coverage_test.dart`.
   - Serveur : `server/i18n` avec `T(lang, fr, args...)` (ADR-0138) et synchronisation dans `server/i18n/en.go`.
4. **Design System & Harmonie Multiplateforme** : Direction *Quiet Premium* (`PROJECT_DESIGN.md`).
   - Tokens stricts : `AppColors` et `AppMotion` (zéro couleur brute `Color(0x...)`, zéro `Duration` brute).
   - Composants imposés : `AppSlider`, `TvDeferredKeyboard`, `AppNetworkImage`, `LoadingView`/`EmptyStateView`/`ErrorStateView`, `SettingsPage`/`Tile`, `Responsive`.
   - TV D-Pad 10-foot UI : Focus visible permanent (ADR-0008), touches `kTvSelectKeys` / `kTvBackKeys`, mémoire du focus.
5. **Gestion du Cycle de Vie & Zéro Fuite Mémoire** :
   - Flutter : Libération systématique dans `dispose()` (`AnimationController`, `TextEditingController`, `FocusNode`, `ScrollController`, `StreamSubscription`, `Timer`). Garde `if (!mounted) return;` après tout `await`. Les animations ne sont pas bridées, mais leurs tickers sont nettoyés à la fermeture.
   - Go : `context.Context` obligatoire pour toute opération I/O, zéro goroutine orpheline non surveillée, fermeture déterministe via `defer close()`.
6. **Sécurité Défensive & Sanitisation** :
   - Confinement des chemins et prévention du Path Traversal via `filepath.Clean()` et validation de racine.
   - Zéro injection SQL : requêtes 100% paramétrées via `?` (`sqlPlaceholders`).
   - Confidentialité : Zéro token JWT, clé d'API, mot de passe ou PII dans les logs (`stdout`/`stderr`).
7. **Résilience Réseau & Offline-First** :
   - Pattern *Stale-While-Revalidate* (SWR) : affichage immédiat du cache local puis revalidation discrète.
   - Timeouts réseau explicites (5-10s max) pour ne jamais figer l'UI.
   - Mode déconnecté autonome : téléchargements locaux lisibles et navigables sans connexion active.
8. **Maintenabilité & Clean Architecture** :
   - Deep Modules (interface étroite, seam unique, zéro shallow wrapper).
   - Fail-fast & Guard clauses dès l'entrée de fonction.
   - Plafond strict de 800 lignes par fichier. Refactoring préalable obligatoire avant tout ajout dans les god-files (`player_screen.dart`, `use_player_controller.dart`, `api_client.dart`, `models.dart`, `emby_sync.go`, `federation.go`).
   - Guard tests automatisés pour verrouiller les conventions critiques.
9. **Économie de tokens via Graphify** :
   - Interrogation obligatoire du graphe `graphify-out/` (`graphify query`, `graphify path`, `graphify explain`) avant toute lecture de code source ou recherche textuelle (`grep`).
   - Lecture ciblée uniquement des lignes identifiées.
   - Exécution de `graphify update .` après modification de code.
   - Dossiers interdits en lecture : `app/build/`, `server/downloads/`, `server/data/`, etc.
   - Transmission obligatoire du protocole Graphify dans les sous-agents.

## Agent skills

### Standards d'ingénierie
Pour tout code de ce dépôt, charger le skill `onyx-engineering` (`.claude/skills/onyx-engineering/`).

### Issue tracker
Issues and PRDs live as GitHub issues in this repo. See `docs/agents/issue-tracker.md`.

### Domain docs
Single-context — one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
