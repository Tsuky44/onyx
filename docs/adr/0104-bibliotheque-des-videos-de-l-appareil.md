# ADR-0104 — Une bibliothèque des vidéos de l'appareil, sans serveur

- **Statut :** accepté, réalisé — testé sur macOS (scan, persistance) ; Android et iOS compilés, pas essayés sur un appareil
- **Date :** 2026-11-03
- **Portée :** `app/lib/services/device_library/`, `app/lib/models/device_video.dart`,
  `app/lib/services/local_playback_source.dart`, `app/lib/screens/device_library/`, le lecteur
  (`player_screen_startup.dart`, `playback_reporter.dart`, `player_controller_tracks.dart`),
  `MainActivity.kt`, `AndroidManifest.xml`, `ios/Runner/Info.plist`.

## Contexte

Installée sans serveur, l'app ne montrait qu'un formulaire de connexion. C'est ce qu'un examen de
store refuse le plus volontiers (« fonctionnalité minimale », une app qui ne sert à rien sans un
compte chez un tiers). Et c'est vrai pour un utilisateur aussi : on ne peut rien essayer avant
d'avoir monté un serveur.

Le lecteur savait déjà lire un fichier sur disque : celui d'un téléchargement hors ligne
(`_localFilePath`, `PlayMethod.local`), sans ticket de lecture ni appel réseau.

## Décision

1. **Des dossiers suivis, rescannés.** `DeviceLibrary` garde la liste des dossiers choisis et
   l'avancement de chaque fichier dans `device_library.json` (Application Support). La liste des
   vidéos n'est pas stockée : elle est refaite à chaque scan, si bien qu'un fichier déplacé hors de
   l'app disparaît sans manifeste à réconcilier. Sur ordinateur, `Directory.watch` relance le scan
   quand un fichier arrive ; sur mobile, l'écran rescanne à l'ouverture et au retour au premier plan.
2. **Par plateforme.**
   - Windows, macOS (hors bac à sable), Linux : n'importe quel dossier, par `file_picker`.
   - Android : un dossier choisi, lu après la permission `READ_MEDIA_VIDEO` (13+) ou
     `READ_EXTERNAL_STORAGE` (≤ 12), demandée par `MainActivity` sur le canal `onyx/device` plutôt
     que par un plugin de permissions.
   - iOS : un dossier choisi ne reste pas lisible d'un lancement à l'autre sans signets de sécurité.
     Le dossier Documents de l'app est donc suivi d'office et exposé dans Fichiers et le Finder
     (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`) ; « Importer » y déplace les
     fichiers choisis.
   - Apple TV, téléviseurs Android et web : rien (`isSupported` faux, les entrées disparaissent).
3. **Des identifiants négatifs.** Le lecteur désigne un média par un entier. Une vidéo de l'appareil
   en reçoit un, négatif, dérivé de son chemin (FNV-1a) : il ne croise jamais un identifiant de
   serveur, et `isDeviceVideoId` suffit à tout aiguillage.
4. **Le lecteur reste unique.** `localPlaybackPath` tranche entre vidéo de l'appareil et
   téléchargement ; le reste du lecteur ne sait pas lequel il lit. Pour une vidéo de l'appareil :
   l'avancement va sur disque et jamais au serveur, la reprise vient du disque, le logo, la reprise
   sur un autre appareil et la rangée « Continuer » sont sautés. Elle part toujours comme un film :
   un épisode lancerait la navigation entre épisodes, qui interroge le serveur.
5. **Deux portes.** Un lien sous le formulaire de connexion, et une tuile en tête de l'onglet
   Hors ligne.

## Conséquences

- L'app est utilisable dès l'installation, sans compte.
- Pas de menu de pistes pour une vidéo de l'appareil : la liste canonique des pistes vient du
  serveur (« Unified Strategy » du contrôleur), et le moteur garde celles que le fichier marque par
  défaut. La construire depuis les pistes du moteur est la suite naturelle.
- Pas de vignettes ni de métadonnées TMDB : il faudrait décoder une image de chaque fichier, et une
  vidéo personnelle n'a pas de fiche à retrouver.
- Google Play demande de justifier `READ_MEDIA_VIDEO` ; un lecteur de vidéos personnelles est l'usage
  que la règle admet.
