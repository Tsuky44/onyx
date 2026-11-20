# Ligne de base du libmpv sous Windows

Premier pas de la phase 1 de l'[ADR-0158](adr/0158-libmpv-officiel-et-rendu-d3d11-sous-windows.md).
On mesure ici le libmpv livré aujourd'hui (shinchiro, capture du 30/08/2026), **avant** que la
version de test du libmpv officiel 0.42.0 n'arrive sur la machine. Chaque porte de l'ADR se juge
contre ces chiffres, pas à l'œil.

Le corpus complet et la procédure générale sur appareil sont dans le
[banc de qualité de lecture](validation-lecture.md). Cette page n'en garde que ce qui sert à
comparer deux libmpv.

## Le jeu de fichiers de référence

Un fichier par ligne du tableau de parité de l'ADR-0158. Les fichiers restent sur le serveur : ne
rien committer. Remplacer « à choisir » par le titre exact dans la bibliothèque, et garder ce même
fichier pour toutes les mesures.

| # | Domaine | Fichier (titre dans la bibliothèque) | Vidéo | Audio | Sous-titres | Ce qu'on regarde |
|---|---|---|---|---|---|---|
| 1 | Codecs vidéo | à choisir | H.264 1080p SDR | AAC stéréo | SRT externe | image, démarrage, `hwdec-current` = `d3d11va-copy` |
| 2 | Codecs vidéo | à choisir | HEVC 1080p 8 bits | AC-3 5.1 | — | image, pas de bande verte en bas |
| 3 | Codecs vidéo | à choisir | HEVC 2160p 10 bits HDR10 | E-AC-3 (Atmos) | PGS | tone mapping juste, charge processeur, images perdues |
| 4 | Codecs vidéo | à choisir | AV1 1080p | Opus ou AAC | ASS (styles) | décodage matériel si le GPU le sait, sinon logiciel sans saccade |
| 5 | Codecs vidéo | à choisir | VC-1 ou MPEG-2 (ancien Blu-ray, DVD) | AC-3 | VobSub | image, sous-titres images |
| 6 | Codecs audio | à choisir | n'importe | **TrueHD** 7.1 | — | son présent, downmix « dialogue en avant » (ADR-0005) |
| 7 | Codecs audio | à choisir | n'importe | **DTS-HD MA** et DTS cœur | — | son présent sur les deux pistes, changement de piste |
| 8 | Codecs audio | à choisir | n'importe | FLAC | WebVTT externe | son, sous-titres |
| 9 | Sous-titres | à choisir (chaîne en direct HLS) | — | — | sous-titres en direct HLS | sous-titres qui arrivent avec l'image |
| 10 | Réseau | le n° 3, ouvert en HTTPS par l'adresse publique | — | — | — | `flux par le relais local` dans `PLAYER STARTUP`, démarrage |
| 11 | Transcodage | le n° 3, qualité forcée à 1080p puis « Auto » | — | — | — | HLS à chaque palier, session préparée |
| 12 | Moteur | deux épisodes qui se suivent | — | — | — | enchaînement, réutilisation du moteur, image dans l'image |
| 13 | Dolby Vision 5 | à choisir | HEVC DV profil 5 | n'importe | — | fenêtre `gpu-next` (ADR-0061), couleurs justes |
| 14 | Durée | un film de deux heures | n'importe | n'importe | n'importe | mémoire stable, son calé jusqu'au bout |

## Le protocole

### Ce qu'on compare

Une seule chose change entre les deux colonnes : le libmpv. Le reste du code est le même commit,
compilé de la même façon, sur la même machine.

- **Ligne de base** : la branche `tsuky` telle qu'elle est avant le changement de binaire (libmpv
  shinchiro). Le changement attend sur la branche locale `tsuky-libmpv-042`.
- **Phase 1** : la même chose après `git merge --ff-only tsuky-libmpv-042` (libmpv 0.42.0).

Les deux se lancent en mode profile, depuis `app/`, avec `STORE_BUILD` pour que la mise à jour
automatique ne remplace pas la version mesurée :

```
flutter run --profile -d windows --dart-define=STORE_BUILD=true
```

Pas en debug : le Dart y tourne en JIT, et la charge mesurée ne dit rien de la version publiée. Pas
non plus la version de prod installée : elle n'a pas le même code que `tsuky`, la comparaison
changerait deux choses à la fois. Le premier lancement après le merge réextrait le libmpv tout seul
(le fichier témoin de l'ADR-0019 ne correspond plus).

Pour savoir quelle DLL tourne : propriétés de `libmpv-2.dll` (dans
`app\build\windows\x64\runner\Profile\`, ou le dossier d'installation d'une version publiée), onglet
« Détails », « Version du produit » : `v0.41.0-1012-ge8673660a` pour shinchiro, `v0.42.0` pour
l'officielle.

Ensuite, la version de test publiée part chez un testeur Windows en HTTPS pendant une semaine
(porte de l'ADR-0158). Ce tableau ne la remplace pas.

### Les conditions

- Machine de référence : noter le processeur, le GPU, le pilote, l'écran (définition, fréquence),
  la sortie audio.
- Même serveur, en HTTPS par l'adresse publique (donc par le relais de l'ADR-0036), même réseau.
- Rien d'autre d'ouvert de lourd. Fenêtre de l'app agrandie, pas en plein écran (le plein écran
  se teste à part, dans la liste de parité).
- Chaque fichier : un démarrage à froid (app fraîchement lancée), puis deux à chaud (on ferme le
  lecteur, on relance le même fichier). Toujours depuis le même point : le début, ou la même
  position de reprise.

### Les mesures, par fichier

1. **Démarrage** : la ligne `PLAYER STARTUP:` du journal de la lecture (Réglages → Historique, toucher
   la lecture, « Journal de lecture », bouton Copier). Noter `playing=` et l'étape la plus longue
   (`plus long : …`).
2. **Processeur et GPU moyens sur 2 minutes** : à partir de 30 s de lecture, sans toucher à rien,
   ouvrir l'Analyseur de performances (`perfmon`), compteurs `Processus(app)\% temps processeur`
   divisé par le nombre de cœurs logiques, et `Moteur GPU(pid_…_engtype_3D)\Utilisation` +
   `…engtype_VideoDecode`. Moyenne sur 120 s. À défaut, le Gestionnaire des tâches, onglet
   « Détails », colonnes « Processeur » et « GPU », relevé toutes les 10 s et moyenné.
3. **Images perdues** : panneau de statistiques du lecteur, ligne « Images perdues », relevée au
   départ puis après les 2 minutes.
4. **`hwdec-current`** : panneau de statistiques, ligne « Décodeur vidéo ».

Pour le n° 14, relever en plus la mémoire de l'app (Gestionnaire des tâches) toutes les 15 minutes
et le décalage du son à la fin.

### Le jugement (porte de la phase 1)

- Toute la liste de parité passe.
- Démarrage et charge (processeur, GPU) à ±10 % de la ligne de base, fichier par fichier.
- Images perdues et décodeur identiques.

## Le relevé

Une ligne par fichier. Démarrage : médiane des trois lancements (froid / chaud / chaud entre
parenthèses si l'écart est grand).

Machine : _à remplir_ · Commit de la ligne de base : _à remplir_ · Commit après le merge : _à remplir_

| # | Démarrage shinchiro | Démarrage 0.42.0 | CPU shinchiro | CPU 0.42.0 | GPU shinchiro | GPU 0.42.0 | Images perdues shinchiro | Images perdues 0.42.0 | `hwdec-current` shinchiro | `hwdec-current` 0.42.0 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| 4 | | | | | | | | | | |
| 5 | | | | | | | | | | |
| 6 | | | | | | | | | | |
| 7 | | | | | | | | | | |
| 8 | | | | | | | | | | |
| 9 | | | | | | | | | | |
| 10 | | | | | | | | | | |
| 11 | | | | | | | | | | |
| 12 | | | | | | | | | | |
| 13 | | | | | | | | | | |
| 14 | | | | | | | | | | |

## Ce qui a déjà été mesuré hors de l'app (2026-11-19)

Les deux DLL chargées seules (`vo=null`, `ao=null`), sur la machine de développement, par le relais
`CONNECT` d'un script de test qui résout le nom lui-même. Ce n'est pas la ligne de base : ça ne
remplace pas les mesures dans l'app ci-dessus.

| Mesure | shinchiro | 0.42.0 |
|---|---|---|
| Ouverture HTTPS jusqu'à `FILE_LOADED`, fichier derrière Cloudflare, médiane de 5 | 170 ms | 111 ms |
| Ligne `CONNECT` reçue par le relais après `loadfile` | +80 ms (requête DNS HTTPS-RR d'abord) | +3 ms |
| TLS vers le serveur Onyx derrière Cloudflare par le relais | TLS 1.3, h2, certificat vérifié | TLS 1.3, h2, certificat vérifié |

Le détail est dans le journal d'avancement de l'ADR-0158.
