# Onyx — Directives d'Ingénierie, Architecture & Standards de Code (CLAUDE.md)

Ce document constitue la **source de vérité absolue** pour tout développement, refactoring, revue de code et intervention d'agent IA dans le dépôt **Onyx**. Il synthétise les exigences de maintenabilité, d'architecture, de design cross-platform, de localisation stricte, de documentation technique (ADR), de sécurité, de gestion du cycle de vie et d'optimisation de tokens via Graphify.

---

## 1. Philosophie & Principes d'Ingénierie de Haut Niveau

### 1.1 Travail silencieux, récapitulatif final structuré
- Pendant l'exécution d'une tâche, travaille en **silence complet** : enchaîne les lectures ciblées, modifications de code et exécutions de commandes sans paraphraser chaque action.
- Le seul message autorisé en cours de route est une **question bloquante** (arbitrage métier ou décision irréversible incombant à l'utilisateur).
- À la fin de chaque session ou étape, produis systématiquement le récapitulatif structuré défini à la section 10.

### 1.2 "Deep Modules" & Encapsulation Forte (*A Philosophy of Software Design*)
- Favorise les **modules profonds** (*Deep Modules*) : chaque module, classe ou service doit exposer une **interface publique étroite et minimale**, tout en encapsulant une logique métier substantielle derrière un unique point de suture (*seam*).
- Bannis les *shallow wrappers* (wrappers creux qui se contentent de relayer des appels sans valeur ajoutée).
- L'appelant ne doit jamais connaître les détails d'implémentation internes (SQL, HTTP, état de bas niveau).

### 1.3 Clean Architecture & Découplage du Domaine
- **Le serveur décide, le client affiche** : Le serveur Go (+ SQLite) est la seule source de vérité pour les permissions, droits d'accès, progression de lecture, statuts et synchronisation.
- **UI optimiste & réconciliation** : Côté client Flutter, une modification d'état optimiste est tolérée uniquement pour la fluidité perçue, mais la réponse du serveur doit systématiquement la valider ou la réconcilier.
- **Frontières strictes** : Découplage total entre la présentation (Widgets), la logique d'état (`ChangeNotifier`, Providers, Hooks) et la couche réseau/données (`services/api/`, `ApiClient`).

### 1.4 Single Source of Truth (SSOT) & Anti-Duplication
- Chaque constante, helper, règle de conversion ou composant UI doit posséder **un point de définition unique** :
  - SQL : `sqlPlaceholders`, `scanSQLiteTime`.
  - UI : `Responsive`, `AppColors`, `AppMotion`, `AppNetworkImage`, `glass_chrome.dart`.
- Interdiction formelle de recréer un helper local avant d'avoir vérifié s'il existe déjà dans `widgets/global/` ou `utils/`.

### 1.5 Plafond de Taille des Fichiers & Dette des Fichiers-Dieux
- **Plafond strict : aucun fichier ne doit dépasser 800 lignes.**
- **Fichiers-dieux identifiés** :
  - Flutter : `player_screen.dart`, `use_player_controller.dart`, `api_client.dart` (les sous-domaines vont dans `services/api/` en mixins `part of`), `models.dart`.
  - Go : `emby_sync.go`, `federation.go`.
- **Règle du boy-scout obligatoire** : Interdiction d'ajouter du code dans l'un de ces fichiers sans en extraire préalablement le widget, hook, helper ou sous-package que tu touches dans son propre fichier.

### 1.6 Guard Tests comme Garde-Fous Architecturaux
- Ne te repose pas sur la mémoire humaine ou des règles écrites passives : **toute convention critique doit être verrouillée par un test automatisé analysant le code** (ex: `app/test/no_bare_text_field_test.dart`, `app/test/l10n_coverage_test.dart`).
- Si une nouvelle règle d'architecture transverse est introduite, elle doit arriver avec son propre *guard test*.

---

## 2. Économie Radicale de Tokens — Protocole Graphify & AST

Pour préserver la fenêtre de contexte et minimiser la consommation de tokens, l'exploration de la base de code repose sur le graphe de connaissances situé dans `graphify-out/`.

### 2.1 Règle d'or de recherche
- **Interdiction formelle** de lancer des recherches en texte brut (`grep`, `find_in_files`, etc.) ou de lire des fichiers sources entiers au hasard dès la première étape.
- **Toujours interroger Graphify en premier** dès qu'il existe `graphify-out/graph.json` :
  - Question d'architecture / localisation d'un symbole :
    ```bash
    graphify query "<question technique ou nom de feature>"
    ```
  - Compréhension des flux et dépendances entre modules :
    ```bash
    graphify path "<ComposantA>" "<ComposantB>"
    ```
  - Explication ciblée d'un sous-système sans gonfler le contexte :
    ```bash
    graphify explain "<concept>"
    ```
- Ne lire les fichiers sources bruts **que pour les plages de lignes exactes** isolées par le graphe ou le skill AST (`smart-explore`).

### 2.2 Navigation macro
- Utilise `graphify-out/wiki/index.md` pour l'orientation globale du dépôt.
- Ne lis `graphify-out/GRAPH_REPORT.md` qu'en cas d'audit d'architecture globale ou si `query`/`path`/`explain` ne fournissent pas de contexte suffisant.

### 2.3 Maintien à jour du graphe
- Après toute modification de code (fichiers Go ou Dart créés/modifiés/déplacés), lance systématiquement :
  ```bash
  graphify update .
  ```
  *(Cette commande est purement AST locale et ne consomme aucun token d'API).*
- Ne t'alarme pas d'un diff volumineux sur `graphify-out/graph.json` dans un commit/PR : le graphe est régénéré en bloc, ce comportement est normal et attendu.

### 2.4 Répertoires strictement exclus en lecture LLM
Ne jamais tenter de lire ou indexer les dossiers suivants (bloqués ou trop volumineux) :
- `app/build/`
- `app/macos/build_xcode/`
- `app/windows/flutter/ephemeral/`
- `.claude/worktrees/`
- `server/downloads/`
- `server/data/`
- `app/.dart_tool/`

### 2.5 Propagation aux sous-agents
Lorsque tu invoques un sous-agent de recherche ou d'implémentation, inclus **obligatoirement** la directive Graphify dans son prompt :
> *« Interroge d'abord graphify-out/ via graphify query/path avant toute lecture de fichier ou recherche grep. Ne lis que les lignes ciblées. »*

---

## 3. Architecture Decision Records (ADR) — Source de Vérité Technique

Le dossier `docs/adr/` est le registre historique et prescriptif des décisions d'architecture d'Onyx.

### 3.1 Consultation préalable obligatoire
- Avant de concevoir ou d'implémenter un changement dans un sous-système (lecteur, transcodage, auth, multi-serveurs, cache, focus TV, navigation...), recherche et lis obligatoirement les ADRs correspondantes dans `docs/adr/`.
- Les ADRs sont rédigées en français : recherche par concept-clé ou par chemin de fichier référencé.
- Tu ne commences à coder que lorsque tu connais les ADRs qui contraignent la zone et le *seam* approprié.

### 3.2 Rédaction systématique d'une nouvelle ADR
Toute décision ayant un impact architectural, structurel ou difficile à défaire doit être consignée dans une nouvelle ADR :
- Fichier : `docs/adr/00NN-titre-en-kebab-case.md` (numérotation incrémentale à la suite de la dernière).
- Rédigée en **français**, respectant scrupuleusement la structure canonique :
  1. **Titre** : `# ADR-00NN — Titre explicite`
  2. **Métadonnées** : `Statut` (accepté / proposé / remplacé), `Date` (YYYY-MM-DD), `Portée` (fichiers/packages touchés).
  3. **Contexte** : Le problème concret, les contraintes observées, pourquoi la solution évidente ne suffit pas.
  4. **Décision** : Le choix technique arrêté, avec points précis numérotés.
  5. **Alternatives écartées** : Les approches analysées et la raison objective de leur rejet.
  6. **Conséquences** : Les compromis assumés, les impacts positifs et négatifs, les suites attendues.

### 3.3 Règle stricte des conflits d'ADR
- **Interdiction absolue d'outrepasser silencieusement une ADR existante.**
- Si ton implémentation s'écarte d'une ADR ou la rend caduque, tu dois obligatoirement le formuler de manière explicite dans ton code et dans la nouvelle ADR :
  > *« Contredit l'ADR-00NN ([Titre]) parce que [justification technique étayée] »*.

---

## 4. Internationalisation (i18n / l10n) — Règle du 100 % Zéro Texte en Dur

Onyx dessert des utilisateurs francophones, anglophones et internationaux. **Aucune chaîne visible par l'utilisateur ne doit être codée en dur dans l'interface ou les réponses serveur.**

### 4.1 Côté Client Flutter (`app/`) — ADR-0047
- **Le texte français écrit dans le code est la clé de traduction.**
- **Enveloppe obligatoire `tr()`** : Tout libellé, titre, bouton, tooltip, message d'erreur ou texte d'aide doit être encapsulé :
  ```dart
  // Correct
  Text(tr('Reprendre la lecture'))
  Text(tr('Saison {0} · Épisode {1}', [seasonNumber, episodeNumber]))

  // Strictement interdit (texte brut ou interpolation directe)
  Text('Reprendre la lecture')
  Text('Saison $seasonNumber · Épisode $episodeNumber')
  ```
- **Pluriels stricts via `trPlural()`** :
  ```dart
  // Correct (prend en compte la règle grammaticale de la langue active)
  Text(trPlural(count, '{0} film', '{0} films'))

  // Interdit (concaténation manuelle artisanale)
  Text('$count film(s)')
  ```
- **Synchronisation bilingue immédiate** :
  - Chaque nouveau texte ajouté avec `tr('...')` DOIT obligatoirement être ajouté dans le dictionnaire `app/lib/l10n/en.dart` (`kEnglish`) au sein de la même tâche.
  - La clé anglaise doit respecter les arguments `{0}`, `{1}` de la clé française.
- **Formats localisés** : Utilise systématiquement `LocaleFormats` pour le formatage des dates, nombres, durées et monnaies (`locale_formats.dart`).
- **Guard test de couverture l10n** :
  - Tout ajout ou modification doit valider :
    ```bash
    flutter test test/l10n_coverage_test.dart
    ```
  - Le test doit rester 100 % vert (zéro clé manquante, zéro divergence d'arguments).

### 4.2 Côté Serveur Go (`server/`) — ADR-0138
- Les messages d'erreur HTTP et de statut retournés par l'API doivent s'adapter à la langue du client via l'en-tête `Accept-Language`.
- Utilise le package `server/i18n` avec `T(lang, fr, args...)` :
  ```go
  // Les fonctions de réponse JSON intègrent la langue de la requête via le middleware
  writeJSONError(w, http.StatusForbidden, "Vous n'avez pas le droit de faire cela")
  ```
- Toute nouvelle chaîne d'erreur serveur doit être ajoutée dans la table de traduction correspondante (`server/i18n/en.go`), triée alphabétiquement.

### 4.3 Résilience UI face à l'expansion textuelle
- Les langues traduites (anglais, allemand, espagnol) peuvent occuper 20 % à 40 % d'espace en plus que le français.
- Vérifie que les boutons, tuiles de réglages et en-têtes ne provoquent aucun débordement (`A RenderFlex overflowed by ... pixels`).
- Utilise `Flexible`, `Expanded`, `TextOverflow.ellipsis` ou des conteneurs à hauteur intrinsèque lorsque nécessaire.

---

## 5. Design System & Harmonie Multiplateforme (Quiet Premium)

L'interface d'Onyx applique la direction artistique **Quiet Premium** définie dans `PROJECT_DESIGN.md`. Le média (affiches, backdrops) est la star émotionnelle ; le chrome de l'application reste discret, sombre et s'efface.

### 5.1 Tokens Obligatoires — Zéro Valeur Magique
- **Couleurs (`theme/app_colors.dart`)** :
  - Arrière-plan scène OLED : `AppColors.background` (`#0A0A0A`).
  - Surfaces élevées : `AppColors.surface` (`#141414`), `AppColors.surfaceElevated` (`#1C1C1C`).
  - Accent / Focus : `AppColors.accent` (`#0A84FF`), utilisé avec parcimonie (≤ 5 % de la surface visible).
  - Typographie : `AppColors.textPrimary` (`#F5F5F7`), `AppColors.textSecondary` (`#A1A1A6`), `AppColors.textMuted` (`#6E6E73`).
  - **Interdiction absolue** d'introduire des couleurs brutes `Color(0x...)`. Convertis les couleurs existantes des fichiers que tu touches vers les tokens officiels.
- **Mouvements & Animations (`theme/app_motion.dart`)** :
  - Durées standardisées : `AppMotion.micro` (180 ms), `AppMotion.standard` (240 ms), `AppMotion.emphasis` (280 ms).
  - Courbe unique : `AppMotion.curve`.
  - Respect de l'accessibilité :
    - `AppMotion.fade(context)` pour l'opacité et les changements de couleur (maintenu sous « Réduire les animations »).
    - `AppMotion.move(context)` pour les mouvements géométriques (ramené à 0 si motion réduite).
  - **Interdiction absolue** d'écrire des `Duration(milliseconds: ...)` brutes pour des transitions d'interface.

### 5.2 Composants Imposés pour l'Harmonie Visuelle
Pour garantir une uniformité parfaite des menus, boutons et éléments d'interaction sur l'ensemble des plateformes :

| Besoin UI | Composant Imposé | Raison / Référence |
|---|---|---|
| **Curseurs / Barres de progression** | `AppSlider` | Le `Slider` Material natif fige l'arbre d'accessibilité sous Windows (ADR-0024). |
| **Champs de texte / Recherche** | Enveloppé par `TvDeferredKeyboard` | Sur Android TV, le clavier plein écran piège le focus. Vérifié par `no_bare_text_field_test.dart`. |
| **Affichage d'images / Affiches** | `AppNetworkImage` + `poster_url.dart` | Décodage à l'échelle d'affichage exacte, gestion du cache mémoire/disque, pas de fuite mémoire. |
| **États asynchrones** | `LoadingView`, `EmptyStateView`, `ErrorStateView` | Cohérence totale des trois états obligatoires (données, vide, erreur avec bouton d'action réessayable). |
| **Menus & Écrans de Réglages** | `SettingsPage`, `SettingsGroup`, `SettingsTile` | Mise en page, densité, espacement et alignement harmonisés (`settings_ui.dart`). |
| **Effet verre & panneaux flottants** | `glass_chrome.dart`, `liquid_glass_panel.dart` | Un seul rendu de verre givré. À doser avec modération (le coût du blur est élevé sur GPU desktop intégré). |
| **Mise en page adaptative** | `Responsive` (`utils/responsive.dart`) | Points de rupture stricts, marges standardisées, cibles tactiles minimales de 48 dp sur mobile. |

### 5.3 TV D-Pad & Expérience 10-Foot (Android TV / tvOS)
Tout écran accessible sur TV doit se piloter intégralement à la télécommande :
- **Touches de navigation** : Toujours utiliser `kTvSelectKeys` et `kTvBackKeys` (`tv/tv_focus.dart`). Ne jamais redéfinir localement la capture des touches.
- **Focus visible en permanence** (ADR-0008) : Anneau de focus bleu mesuré (`#0A84FF`), épaisseur 2px, contraste OLED impeccable.
- **Mémoire du focus** : Lors du retour sur un écran ou du défilement d'un carrousel, le focus doit revenir sur le dernier élément sélectionné via `tv_focus_memory.dart` et `tv_focus_rows.dart`.
- **Échelle d'interface TV** : Respecte les ratios définis dans `tv_ui_scale.dart`.
- **Tests de focus obligatoires** : Tout écran TV modifié ou créé doit disposer d'un test de navigation au D-pad sur le modèle de `app/test/tv_focus_test.dart`.

---

## 6. Gestion du Cycle de Vie, Fuites Mémoires & Annulation Asynchrone

La fluidité d'un lecteur média dépend de la libération immédiate des ressources inutilisées. **Prévenir les fuites ne bride en rien la richesse des animations** : au contraire, cela garantit un framerate constant à 60/120 FPS en éliminant les saccades (*jank*) causées par les contrôleurs oubliés en arrière-plan.

### 6.1 Règle du Nettoyage Intégral (`dispose`) côté Client Flutter
- Tout objet alloué disposant d'un cycle de vie **DOIT** être explicitement détruit dans la méthode `dispose()` de son `State` :
  - `AnimationController` : libérer l'attachement au `TickerProvider` (évite qu'un contrôleur fantôme ne continue de calculer des frames invisibles).
  - `TextEditingController` et `FocusNode` : détacher les écouteurs de saisie système.
  - `ScrollController` et `PageController` : éliminer les listeners d'offset de défilement.
  - `StreamSubscription` et `Timer` : appeler systématiquement `.cancel()`.
- **Garde `mounted` obligatoire** : Tout saut asynchrone (`await`) dans un `StatefulWidget` doit impérativement être suivi d'une vérification de montage avant d'appeler `setState()` ou de manipuler le `BuildContext` :
  ```dart
  final result = await fetchPlaybackProgress();
  if (!mounted) return;
  setState(() => _progress = result);
  ```
- **Déréférencement des Listeners** : Tout abonnement manuel à un `ChangeNotifier` (`addListener`) doit posséder son pendant exact dans `dispose()` (`removeListener`).

### 6.2 Propagation de Contexte & Contrôle des Goroutines côté Serveur Go
- **Context Obligatoire** : Toute fonction effectuant des opérations réseau, disque ou base de données doit accepter un `context.Context` en premier paramètre et le respecter.
- **Zéro Goroutine Orpheline** :
  - Interdiction absolue des goroutines détachées ("fire-and-forget") sans mécanisme d'arrêt.
  - Chaque goroutine asynchrone doit écouter l'annulation du contexte :
    ```go
    go func(ctx context.Context) {
        select {
        case <-ctx.Done():
            return
        case work := <-workQueue:
            process(work)
        }
    }(ctx)
    ```
- **Fermeture Déterministe des Descripteurs** :
  - Tout corps de réponse HTTP (`resp.Body`), curseur SQLite (`rows`) ou descripteur de fichier (`file`) doit être fermé immédiatement après allocation via `defer resource.Close()`.

---

## 7. Sécurité Défensive, Sanitisation & Protection des Données

En tant que serveur auto-hébergé exposé sur des réseaux locaux et distants, Onyx applique le principe de défense en profondeur.

### 7.1 Prévention Stricte du Path Traversal
- Tout chemin de fichier construit à partir d'un identifiant, nom de média ou paramètre utilisateur doit être sanitisé :
  1. Utilisation obligatoire de `filepath.Clean()`.
  2. Vérification systématique du confinement dans le répertoire racine attendu :
     ```go
     cleanPath := filepath.Clean(filepath.Join(rootDir, userInput))
     if !strings.HasPrefix(cleanPath, rootDir + string(filepath.Separator)) {
         return ErrForbiddenPath
     }
     ```
- Les téléchargements locaux et les flux multimédias servis ne doivent jamais permettre d'accéder au système de fichiers hôte hors des dossiers explicitement déclarés.

### 7.2 Immunité aux Injections SQL & Requêtes Paramétrées
- **Interdiction formelle** d'utiliser `fmt.Sprintf` ou des concaténations de chaînes pour assembler des clauses SQL.
- Utilise exclusivement les requêtes paramétrées avec des points d'interrogation `?` et les utilitaires `sqlPlaceholders` :
  ```go
  // Correct
  query := "SELECT id, title FROM media WHERE library_id = ? AND status = ?"
  rows, err := db.QueryContext(ctx, query, libraryID, status)

  // Strictement banni
  query := fmt.Sprintf("SELECT id FROM media WHERE library_id = '%s'", libraryID)
  ```

### 7.3 Protection des Données Privées & Sanitisation des Logs
- **Zéro PII et Zéro Secret dans les logs** :
  - Ne jamais imprimer de tokens d'authentification (JWT), clés d'API (TMDB), mots de passe en clair ou codes PIN d'appairage TV dans `stdout`, `stderr` ou les fichiers de log.
  - Les erreurs renvoyées ou loguées doivent être expurgées de données sensibles : logger la cause interne côté serveur, renvoyer un message d'erreur générique et sûr au client.
- **Limitation de taille des requêtes HTTP** :
  - Les endpoints recevant des payloads JSON ou des fichiers doivent protéger la mémoire contre les attaques DoS via `http.MaxBytesReader`.

---

## 8. Résilience Réseau, Stratégie de Cache & Mode Hors-Ligne (Offline-First)

Onyx est conçu pour offrir une expérience fluide, même face à un réseau dégradé ou inexistant (mode avion, mobilité, coupures de courant locales).

### 8.1 Pattern Stale-While-Revalidate (SWR)
- Lorsqu'une vue sollicite des données déjà connues (catalogue, progression de lecture, réglages) :
  1. Afficher immédiatement la version présente dans le cache local (mémoire ou stockage permanent).
  2. Lancer la revalidation réseau en arrière-plan sans bloquer l'UI.
  3. Mettre à jour l'écran de manière fluide dès réception de la réponse fraîche, sans scintillement ni réinitialisation du scroll.

### 8.2 Timeouts Déterministes & Dégradation Gracieuse
- Aucun appel réseau ne doit attendre indéfiniment. Applique des timeouts explicites :
  - Requêtes API standards : 5 à 10 secondes maximum.
  - Streaming / Téléchargement : monitoring de débit avec reconnexion intelligente.
- En cas d'échec réseau, ne laisse jamais l'écran dans un état figé : bascule gracieusement sur `ErrorStateView` (avec bouton « Réessayer ») ou affiche les données en cache accompagnées d'un indicateur de déconnexion discret.

### 8.3 Autonomie Déconnectée Complète (Offline-First)
- **Démarrage sans connexion** : L'app démarre instantanément sans réseau grâce aux polices embarquées (ADR-0025) et aux préférences locales persistées.
- **Section Téléchargements autonome** :
  - Tout média téléchargé en local (`screens/downloads/`) doit être consultable et lisible sans aucune requête réseau préalable vers le serveur.
  - La progression de lecture hors-ligne est enregistrée localement et synchronisée avec le serveur dès le rétablissement de la connectivité.

---

## 9. Vérifications Locales & Barrière Qualité CI

Avant de clore une tâche ou de valider du code, assure-toi que l'ensemble des vérifications locales sont au vert. La CI GitHub (`.github/workflows/ci.yml`) est intransigeante et bloque tout merge en cas d'erreur.

### 9.1 Vérification Serveur (`server/`)
```bash
# 1. Formatage du code (ne doit rien afficher)
gofmt -l .

# 2. Analyse statique
go vet ./...

# 3. Tests unitaires et race condition detector
go test -race ./...
```

### 9.2 Vérification Client Flutter (`app/`)
```bash
# 1. Analyse statique sans aucun warning
flutter analyze

# 2. Vérification stricte de la couverture de traduction
flutter test test/l10n_coverage_test.dart

# 3. Suite de tests ciblés puis globale
flutter test
```

> **Règle d'intégrité** : Un test qui échouait avant ton intervention doit être signalé explicitement dans le récapitulatif. Il est formellement interdit de désactiver ou de contourner un test existant pour faire passer un build.

---

## 10. Protocole de Fin de Session (Reporting Obligatoire)

À la fin de chaque tâche ou session de travail, fournis **exclusivement un récapitulatif final structuré** au format markdown ci-dessous, sans bavardage superflu :

### Format type du récapitulatif :

```markdown
### 🎯 Récapitulatif de Fin de Session

#### ✅ Fait
- [Description concise de l'implémentation 1] ([fichier_cle.dart](file:///chemin/vers/fichier_cle.dart))
- [Description concise de l'implémentation 2] ([fichier_cle.go](file:///chemin/vers/fichier_cle.go))

#### 🧪 Vérifié
- `go test -race ./...` : ✅ vert (X packages vérifiés)
- `flutter analyze` : ✅ 0 nouveau warning
- `flutter test test/l10n_coverage_test.dart` : ✅ vert (100 % des clés traduites)
- `graphify update .` : ✅ graphe régénéré

#### ❌ Pas fait / Bloqué
- [Éventuelle étape sautée ou dépendance bloquante, ou "Aucun"]

#### 📋 À faire (Next Steps)
- [Prochaine tâche prioritaire immédiate 1]
- [Prochaine tâche prioritaire immédiate 2]

#### 📐 Décisions & ADRs
- **ADRs consultées** : ADR-0047, ADR-0008...
- **ADR créée / amendée** : `docs/adr/00NN-titre.md` (ou "Aucune nouvelle ADR nécessaire pour cette tâche")
```
