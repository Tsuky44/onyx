# Onyx en anglais à 100 % : état des lieux et plan

*Audit du 2026-11-17, sur `main` (65fbff7a). Priorité : l'anglais d'abord, parce qu'il sert
aussi tous les utilisateurs ni francophones ni anglophones (un appareil réglé dans une autre
langue reçoit déjà l'anglais). L'espagnol et l'allemand viendront ensuite (§ 5).*

## 1. Objectif : ce que veut dire « 100 % anglais »

Un utilisateur dont l'app est en anglais :

1. ne voit **aucun mot français** : ni dans l'app, ni dans un message d'erreur du serveur, ni
   dans une fenêtre système (autorisation iOS, notification Android, installeur Windows), ni
   dans les textes légaux ;
2. lit des **formats anglais** : dates, nombres, montants, pluriels ;
3. lit un anglais **relu sur de vrais écrans** (téléphone, TV, bureau), sans texte coupé ni
   tournure maladroite.

Des tests empêchent qu'une nouvelle phrase française se glisse dans l'interface anglaise.

## 2. Où en est l'anglais

| Mesure | Valeur |
|---|---|
| Clés dans `en.dart` | 1 873 (dont 75 identiques à leur clé : noms propres, codes) |
| Appels `tr()` | 2 455, dans 266 fichiers |
| Test `l10n_coverage_test.dart` | ✅ vert (7/7), mais il ne voit que les `tr('littéral')` |
| Fiches TMDB (titres, synopsis) | déjà servies en anglais (ADR-0049) |
| Relecture sur écran réel | **jamais faite** (ADR-0047) |

L'essentiel de l'interface est donc traduit. Ce qui reste se range en six familles.

### 2.1 Textes de l'app affichés en français

Chaque endroit a été vérifié dans le code.

| Fichier | Ce qui reste en français |
|---|---|
| [media_countdown.dart](../app/lib/widgets/global/media_countdown.dart) | Tout le compte à rebours : « Saison X · Épisode Y », « Nouvel épisode », « Prochain épisode », « Film à venir ». Aucun `tr()` dans le fichier |
| [detail_info_table.dart:51-118](../app/lib/widgets/global/detail_info_table.dart) | `formatLanguage` (« Japonais »), `formatCountry` (« Corée du Sud ») et `formatMoney` (« 12 M $US ») renvoient du français sans `tr()`. On les voit sur la fiche d'une demande ([request_info_table.dart:39-88](../app/lib/screens/requests/widgets/request_info_table.dart)) |
| [stats_page.dart:229](../app/lib/screens/settings/pages/stats_page.dart) (+ L248, L314, L499) | « N lecture(s) » |
| [request_info_table.dart:70](../app/lib/screens/requests/widgets/request_info_table.dart) | « N saison(s), N épisodes » |
| [collection_screen.dart:221](../app/lib/screens/library/collection_screen.dart) | « N film(s) · N dans ta bibliothèque » |
| [downloads_header.dart:72](../app/lib/screens/downloads/widgets/downloads_header.dart) (+ L147) | « N élément(s) », « élément(s) supprimé(s) » |
| [download_group_headers.dart:158](../app/lib/screens/downloads/download_group_headers.dart) | « N élément(s) » |
| [download_tv_row.dart:121](../app/lib/screens/downloads/widgets/download_tv_row.dart) | « sur 3,2 Go », passé en argument de `tr` sans être traduit |

Les tables constantes (statuts TMDB, droits, raccourcis du lecteur, tri du catalogue, politique
OTP, durées de partage…) sont traduites au moment de l'affichage et ont toutes leur entrée.
Elles ne posent pas de problème.

### 2.2 Formats

- **Dates** : seul le nom du mois est traduit. L'anglais affiche « 20 October 2026 » et « 3 Oct. ».
  Les fichiers concernés : [long_date.dart](../app/lib/utils/long_date.dart),
  `_shortMonths` dans [format.dart](../app/lib/utils/format.dart), et `formatFrenchDay` (jours de
  la semaine dans `settings_ui.dart`), utilisé par les pages Activité, Partages, Stockage et Stats.
- **Nombres** : [`formatBytes`](../app/lib/utils/format.dart) remplace le point par une virgule
  en dur, d'où « 1,5 GB » au lieu de « 1.5 GB ».
- **Montants** : « 1,2 Md $US » au lieu de « $1.2B ».
- **Pluriels** : les 20 clés de la forme `{0} item{1}` fonctionnent en anglais. Les 31
  `? 's' : ''` écrits hors `tr()` sont ceux du § 2.1.

### 2.3 Serveur

- `writeJSONError` contient **187 messages distincts en français**, plus **28 messages
  dynamiques** (`err.Error()`, `fmt.Sprintf`). L'app les affiche tels quels (connexion, listes,
  demandes, administration…). Un utilisateur anglais lit donc « Vous n'avez pas le droit de faire
  cela. ».
- [home_screen.dart:91](../app/lib/screens/home/home_screen.dart) décide d'un rechargement en
  testant `msg.startsWith('Re-détection')` sur un message du serveur. Ce test cassera dès que le
  serveur répondra en anglais.

### 2.4 Natif

| Endroit | État |
|---|---|
| iOS `Info.plist` : caméra, photos, mouvement, réseau local | français seulement, sans `InfoPlist.strings` ni `CFBundleLocalizations` |
| macOS, tvOS (`Base.lproj`) | même situation |
| Android : notification et canal de téléchargement ([DownloadKeepAliveService.kt](../packages/onyx_background_downloads/android/src/main/kotlin/com/projectplayer/onyx_background_downloads/DownloadKeepAliveService.kt)) | « Téléchargements » et « Progression des téléchargements hors ligne » écrits en dur |
| Installeur Windows ([installer.iss](../app/installer.iss)) | `French.isl` seulement |

### 2.5 Textes légaux

`assets/legal/conditions.txt`, `confidentialite.txt` et `third_party.txt` n'existent qu'en
français. La politique de confidentialité doit être lisible en anglais pour les stores.

### 2.6 Qualité de l'anglais

- **Orthographe mélangée.** On trouve des formes britanniques (*cancelled*, *favourite*,
  *catalogue* × 14) et américaines (*catalog* × 4). Or TMDB est demandé en `en-US`.
- **Widgets Flutter.** `flutter_localizations` n'est pas embarqué. Le menu copier/coller et les
  sélecteurs de date sont donc en anglais, ce qui convient à l'anglais mais pas au français.
- **Relecture.** Aucun écran n'a été relu en anglais : textes coupés, ton et cohérence des termes
  restent à vérifier.

## 3. Plan : anglais complet

Le principe de l'ADR-0047 reste le même : le français est la clé, `en.dart` donne l'anglais.
Les lots A à E sont indépendants et peuvent avancer dans n'importe quel ordre ou en parallèle.
F s'appuie sur A et B, G vient à la fin.

### Lot A : textes de l'app (§ 2.1)

1. Ajouter à `tr.dart` une fonction `trPlural(n, '{0} élément', '{0} éléments')`, avec une
   entrée pour chaque forme dans `en.dart`. C'est une petite fonction, et elle servira telle
   quelle pour l'espagnol et l'allemand. Les 20 anciennes clés `{1}` ne bougent pas pour
   l'instant.
2. Faire passer par `tr()` ou `trPlural()` chaque ligne du § 2.1. Dans `detail_info_table.dart`,
   ajouter `tr()` au retour de `formatLanguage` et `formatCountry`, et compléter `en.dart` avec
   les pays qui manquent (Japon, Chine, Inde, Brésil, Mexique, Corée du Sud, Danemark,
   Norvège…).
3. **Terminé quand** `l10n_coverage_test` est vert et qu'un test widget du compte à rebours et
   de la fiche demande, en anglais, ne trouve aucun texte français.

### Lot B : formats anglais (§ 2.2)

1. Dates : une fonction de formatage par langue, à un seul endroit. Elle rend « October 20,
   2026 », « Oct 3 » et « Monday, October 20 ». Deux solutions : des tables propres à chaque
   langue (sans dépendance), ou `intl` avec `initializeDateFormatting` (plus simple quand
   l'espagnol et l'allemand arriveront). **Recommandé : `intl`**, déjà dans `pubspec.yaml`.
   Renommer `formatFrenchDay` en `formatDay`.
2. `formatBytes` : le séparateur décimal suit la langue.
3. `formatMoney` : « $1.2B », « $12M » en anglais.
4. **Terminé quand** des tests unitaires de `format.dart` et `long_date.dart` vérifient chaque
   format en français et en anglais.

### Lot C : messages du serveur (§ 2.3)

1. Créer un paquet `server/i18n` sur le même principe que l'app : la clé est le texte français,
   un dictionnaire `en` donne l'anglais, et la langue est lue dans l'en-tête `Accept-Language`
   (via `medialang.FromRequest`, que l'app envoie déjà sur chaque requête). `writeJSONError` et
   `writeMediaHubError` traduisent avant d'écrire.
2. Remplacer les 28 messages dynamiques par une phrase à valeurs (`"… {0}"`, args) plutôt que
   `err.Error()` brut. Les erreurs techniques venues d'un service externe restent telles
   quelles, précédées d'une phrase traduite.
3. Remplacer le test `startsWith('Re-détection')` de l'accueil par un champ explicite dans la
   réponse (`"kind": "redetect"`, par exemple).
4. Ajouter un test Go qui extrait chaque littéral de `writeJSONError` et exige son entrée
   anglaise.
5. **Terminé quand** le test Go est vert et qu'un appel avec `Accept-Language: en` sur une route
   refusée renvoie l'anglais. L'outil `go-tests-via-docker` le vérifie.

### Lot D : natif (§ 2.4)

1. iOS, macOS et tvOS : `en.lproj/InfoPlist.strings` et `fr.lproj/InfoPlist.strings` pour les
   descriptions d'autorisation, et `CFBundleLocalizations = [en, fr]`. L'anglais devient la
   langue de repli du système.
2. Android : `res/values/strings.xml` en anglais (le repli) et `res/values-fr/strings.xml`.
   `DownloadKeepAliveService` lit ses textes depuis les ressources.
3. Windows : ajouter `Name: "en"; MessagesFile: "compiler:Default.isl"` dans `[Languages]`.
4. **Terminé quand** chaque plateforme, réglée en anglais, affiche ces textes en anglais. Le
   contrôle se fait à la main (émulateur Pixel 9, simulateur iOS si disponible) et par un test
   qui vérifie que les deux fichiers de chaque paire ont les mêmes clés.

### Lot E : textes légaux (§ 2.5)

1. Rédiger `conditions.en.txt`, `privacy.en.txt` et `third_party.en.txt`. `LegalDocument`
   choisit son fichier selon `AppLanguage`.
2. Ajouter une phrase qui dit quelle version fait foi (§ 4).
3. Publier la version anglaise de la politique de confidentialité à l'URL publique demandée par
   les stores (tâche *store-readiness* encore ouverte).

### Lot F : garde-fous

1. Étendre `l10n_coverage_test.dart` aux tables lues par `tr(variable)` (43 appels). Chaque
   valeur des tables connues (`requestCatalog*`, `permissionLabels`, `_helpRows`, mois, jours,
   pays, langues) doit avoir son entrée.
2. Ajouter un test « pas de français caché » : tout littéral accentué ou contenant un mot
   français courant, hors `tr()`, dans `screens/`, `widgets/` et `tv/`, fait échouer le test. Les
   fichiers de diagnostic (`playback/*_trace`, journaux) sont sur une liste blanche. C'est
   l'heuristique de cet audit, rendue permanente.
3. Embarquer `flutter_localizations` (fr, en) : les widgets système suivent `AppLanguage`.

### Lot G : relecture sur écrans réels

1. Parcourir en anglais les écrans principaux : connexion, accueil, bibliothèque, fiche, lecteur
   (menus pistes et qualité), téléchargements, demandes, listes, regarder ensemble, chaque page
   de réglages, administration. Le faire sur téléphone (émulateur Pixel 9), TV (simulateur
   webOS, Android TV) et bureau (Windows).
2. Noter les textes coupés (l'anglais est souvent plus court, mais pas partout), les termes
   incohérents d'un écran à l'autre et les tournures traduites mot à mot. Corriger dans
   `en.dart`.
3. Uniformiser l'orthographe selon la décision 1 du § 4.
4. **Terminé quand** les écrans relus sont listés dans ce document, avec leurs captures.

### Ordre conseillé

| Lot | Taille | Dépend de |
|---|---|---|
| A Textes de l'app | petite | — |
| B Formats | petite | — |
| C Serveur | moyenne (le plus gros volume : environ 215 messages) | — |
| D Natif | petite | — |
| E Légal | petite à rédiger, plus la relecture juridique | — |
| F Garde-fous | petite | A, B |
| G Relecture | moyenne | tout le reste |

A, B et F d'abord : ils sont rapides et visibles partout. C ensuite, car c'est le plus gros
volume. D et E peuvent avancer en parallèle. G à la fin, sur une app complète.

## 4. Décisions à prendre

1. **Anglais américain ou britannique ?** Recommandé : **américain** (*canceled*, *favorite*,
   *catalog*). Il est cohérent avec TMDB `en-US`, et c'est la variante attendue par défaut
   dans les stores.
2. **Textes légaux** : faut-il une traduction relue juridiquement, ou garder le français comme
   version qui fait foi, avec une traduction anglaise indicative ?
3. **Règle pour les nouvelles phrases** : le test bloque toute phrase sans anglais (c'est déjà
   le cas pour `tr()` et ce serait étendu par le lot F). Recommandé : garder ce blocage.

## 5. Ensuite : espagnol et allemand

Une fois l'anglais complet, ces étapes ajoutent l'espagnol et l'allemand :

- étendre `AppLanguage`, ajouter `es.dart` et `de.dart`, et faire retomber une clé manquante
  sur l'anglais plutôt que sur le français ;
- migrer les 20 clés `{1}` vers `trPlural` (le « s » ajouté est faux en allemand) ;
- adapter la règle de casse des noms de langue de
  [media_tracks.dart:47](../app/lib/models/media_tracks.dart), qui ne prévoit que l'anglais ;
- ajouter `es-ES` et `de-DE` à `medialang.interfaceLocales`, et les dictionnaires au paquet
  `server/i18n` ;
- s'appuyer sur un glossaire, un premier jet automatique et une relecture par des locuteurs
  natifs ;
- dupliquer les fichiers natifs, les textes légaux et les fiches store ;
- contrôler les débordements en allemand (environ 30 % plus long).

Les lots A à F posent déjà la plupart de ces fondations (`trPlural`, formats par langue,
`server/i18n`, ressources natives). Les deux langues coûteront donc surtout la traduction et
sa relecture.
