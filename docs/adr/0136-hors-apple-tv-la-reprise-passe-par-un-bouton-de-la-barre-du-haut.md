# ADR-0136 — Hors Apple TV, la reprise d'un autre appareil passe par un bouton de la barre du haut

- **Statut :** accepté. Couvert par les tests ; **pas encore essayé sur le Fire TV avec la
  télécommande Hisense (HDMI-CEC) ni avec celle du Fire TV**.
- **Date :** 2026-11-17
- **Portée :** `widgets/global/remote_playback_banner.dart` (`RemotePlaybackBanner.playKeys`,
  `_onHoldKey`, `_refresh`), `widgets/global/remote_playback_notice.dart` (`headerFocused`,
  `_hint`), `widgets/global/remote_playback_slot.dart` (`RemotePlaybackSlot`),
  `widgets/global/remote_playback_header_button.dart`, `screens/shell/shell_tv_header.dart`,
  `screens/shell/main_shell.dart`.

## Contexte

ADR-0127 fait reprendre ce que le compte lit ailleurs en **maintenant** lecture/pause, et, hors
Apple TV, rend aussi la notification focalisable, « Bas depuis le compte y mène, OK reprend ».

Retour de l'utilisateur, sur un Fire TV branché à un téléviseur Hisense : « j'ai un bouton pause
play sur la télécommande Hisense mais ça marche pas quand je reste appuyé, et la télécommande Fire
Stick n'a juste pas de play pause ». Trois causes :

1. **Seules « lecture/pause » et « lecture » étaient écoutées.** Par HDMI-CEC, la télécommande du
   téléviseur envoie souvent « lecture » et « pause » séparément ; « pause » ne faisait rien.
2. **Un appui maintenu ne passe pas toujours par HDMI-CEC.** Selon le téléviseur, il arrive en
   « enfoncé, relâché » aussitôt, ou en paires répétées toutes les demi-secondes : l'anneau se vide
   bien avant ses 900 ms.
3. **Le focus de la notification était introuvable.** Elle est posée par-dessus le bandeau, sur le
   chemin d'aucune rangée : il fallait monter au compte, puis descendre. Personne ne le devine, et
   sans touche lecture/pause on n'y revenait pas.

Puis : « et si pour Android, en plus d'avoir la touche pour la reprendre, on faisait un widget qui
serait au même niveau que la barre qui est en haut pour naviguer entre les onglets ».

## Décision

Contredit l'ADR-0127 (point 2, « un appui court ne fait rien », et point 5, la notification prend
le focus) **hors Apple TV seulement**, parce que l'appui maintenu y dépend d'une télécommande
qu'Onyx ne choisit pas.

1. **« Pause » vaut aussi lecture/pause** (`RemotePlaybackBanner.playKeys`), partout, Apple TV
   comprise.
2. **Hors Apple TV, « Reprendre ici » est un bouton de la barre du haut**
   (`RemotePlaybackHeaderButton`), à gauche du compte, au même niveau que les onglets : Haut depuis
   l'accueil mène à la barre, Droite jusqu'à lui, OK reprend. Il n'existe que tant que l'accueil
   annonce une lecture, et disparaît sur un autre onglet. La notification ne prend plus le focus :
   elle s'éclaire quand le bouton l'a, et dit « OK pour reprendre ici ». La coquille possède la
   place (`RemotePlaybackSlot`), l'accueil la remplit, la barre la dessine.
3. **Un appui court sur lecture/pause amène le focus sur ce bouton**, et un second appui (ou OK)
   reprend. Ce sont deux gestes voulus : une lecture ne part toujours pas d'un seul appui machinal.
   Maintenir la touche reprend encore, là où la télécommande sait le faire.
4. **Le bouton prend le focus de lui-même quand la notification arrive avec l'accueil** (ouverture
   de l'app, retour au premier plan, retour d'une autre page), une fois par lecture. C'est le moment
   où l'on prend la télécommande pour reprendre ce que le téléphone lisait, et OK suffit alors, même
   sans touche lecture/pause. Un sondage pendant que l'on parcourt l'accueil ne prend jamais le
   focus.
5. La notification dit « Appuyez pour reprendre ici » tant que le bouton n'a pas le focus, puis
   « OK pour reprendre ici ».
6. **Hors de la coquille** (un accueil monté seul, dans un test), sans barre, c'est la notification
   qui prend le focus, comme avant.

Apple TV ne change pas, sauf le point 1 : pas de bouton, pas de focus, il faut maintenir la touche.

### Écarté

- **Laisser la notification focalisable en plus du bouton.** Deux cibles pour un seul geste, dont
  l'une sur le chemin d'aucune rangée.
- **Allonger le délai de rebond (40 ms) pour couvrir les répétitions HDMI-CEC.** Un appui court
  remplirait alors l'anneau aux deux tiers avant de se vider, et rien ne garantit qu'un téléviseur
  répète la touche.
- **Un appui court qui reprend directement.** C'est ce que l'ADR-0127 a retiré.
- **La touche menu.** Elle ouvre déjà le menu de la carte qui a le focus.

## Conséquences

- Ouvrir Onyx sur le téléviseur pendant que le téléphone lit met le focus sur « Reprendre ici »
  dans la barre au lieu du bouton lecture du bandeau ; OK reprend la lecture du téléphone. Bas en
  sort.
- Si le bandeau de l'accueil arrivait après la notification et forçait son focus, le point 4 ne se
  verrait pas : il prend le sien par `autofocus`, qui ne vole pas un focus déjà posé. À confirmer sur
  appareil.
- Les boutons de droite de la barre (indexation, mise à jour, compte) se décalent d'un disque vers
  la gauche tant que le bouton est là.
- Épinglé par `test/remote_playback_notice_test.dart`, sur les deux systèmes de navigation : avec
  la barre (focus au bouton à l'arrivée et OK, Haut puis Droite depuis l'accueil, appui court puis
  second appui, disparition quand l'autre appareil s'arrête) ; sans barre (focus à l'arrivée, Bas
  depuis le compte, pas de focus volé par le sondage, les trois touches) ; « pause » maintenue sur
  Apple TV.
