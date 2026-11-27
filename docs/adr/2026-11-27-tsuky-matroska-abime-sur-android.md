# Un MKV abîmé se lit quand même sur Android

- **Statut :** accepté
- **Date :** 2026-11-27
- **Portée :** `packages/onyx_player_android` : `MatroskaResync.kt` (nouveau), `PlayerHost.kt`, `test/.../ClusterScanTest.kt`.

## Contexte

1. Un épisode 4K (*The Gentlemen* S01E01, 6,4 Go, écrit par mkvmerge v83) refusait de démarrer sur Android, téléphone comme Firestick, avec `ERROR_CODE_PARSING_CONTAINER_MALFORMED`. Le même fichier se lit sur Windows (mpv) et sur Apple (AetherEngine).
2. Le fichier est abîmé : en trois endroits, 37 à 90 Ko d'octets ne font partie d'aucun bloc, au milieu d'un cluster. Le premier se trouve à 1 Mo du début du fichier.
3. FFmpeg, sur lequel s'appuient mpv et AetherEngine, saute ces octets et reprend au bloc suivant. L'extracteur Matroska de media3 1.11 ne se recale que si l'identifiant d'élément est trop long. Ici, les octets parasites se lisent comme un `ReferenceBlock` dont l'entier annonce 127 octets, et media3 lève `Invalid integer size: 127`.
4. Cette erreur était classée `UNKNOWN`. Le démarrage était donc abandonné sans même tenter le repli sur le HLS du serveur.

## Décision

1. **Un extracteur Matroska qui se recale** (`MatroskaResyncExtractor`), installé par `ResyncingExtractorsFactory` dans la `DefaultMediaSourceFactory`. Sur une `ParserException` « malformée » levée après la lecture des pistes, il cherche le prochain identifiant de Cluster suivi d'une taille EBML valide et d'un Timestamp (ou d'un CRC-32). Il appelle alors `seek()` sur l'extracteur d'origine, ce qui revient au saut vers un repère de l'index, puis renvoie `RESULT_SEEK` vers ce cluster. On perd la fin du cluster abîmé, une demi-seconde sur ce fichier.
2. **Garde-fous** : pas de recalage si l'en-tête est cassé, ni au-delà de 64 Mo parcourus sans trouver de cluster, ni plus de 64 fois par lecture. On ne reprend jamais en arrière de la reprise précédente, sauf après un saut demandé par l'utilisateur. Si l'erreur survient sans aucun cluster après elle, la lecture se termine à cet endroit.
3. **`PARSING_CONTAINER_MALFORMED` est classé `UNSUPPORTED`**. Quand le recalage ne suffit pas, l'app se replie sur le HLS du serveur au palier natif, qui recopie l'image telle quelle.
4. **Le message d'erreur remonté à Dart porte la cause interne**, en plus du « Source error » générique d'ExoPlayer.

## Conséquences

- Les autres conteneurs (MP4, TS…) et le HLS passent par les extracteurs de media3 sans changement.
- Un fichier abîmé se lit sur Android comme sous mpv, avec un accroc d'image à chaque défaut. Un `Log.w` (`OnyxMatroskaResync`) indique la position et le nombre d'octets sautés.
- Une montée de media3 doit revérifier que `MatroskaExtractor.seek()` remet bien le lecteur EBML à zéro sans oublier les pistes. Le recalage repose sur ce comportement.
- `ClusterScanTest` épingle la recherche du cluster : identifiant croisé au hasard, taille invalide, identifiant coupé en fin de morceau, CRC-32. L'extracteur lui-même n'est pas testé sur la JVM, faute d'Android (`SparseArray`). Il a été vérifié en simulant le lecteur EBML de media3 sur le fichier en cause.
