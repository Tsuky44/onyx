# ADR 2026-11-23 (fytroz) : l'intention de lecture est retenue, jamais relue du moteur

- **Statut :** accepté. Le Dart est analysé et testé ; **le Swift n'a été ni compilé ni lancé**
  (pas de Xcode ici), et rien n'a tourné sur une Apple TV.
- **Date :** 2026-11-23
- **Portée :** `app/lib/screens/player/playback/playback_intent.dart` (nouveau),
  `hooks/player_controller_transport.dart` (nouveau), `hooks/use_player_controller.dart`,
  `hooks/player_controller_hls.dart`, `hooks/player_controller_cut.dart`,
  `hooks/use_player_watch_party.dart`, `player_screen.dart`, `player_screen_flow.dart`,
  `player_screen_chrome.dart`, `player_screen_pause_info.dart`,
  `packages/onyx_player_apple` (`AetherPlayer.swift`, copie `tvos/` comprise), AetherEngine 7.42.
- **Prolonge** l'[ADR-0093](0093-changement-de-piste-audio-et-premier-segment-sur-apple.md)
  (le play/pause retenu pendant un chargement) et l'[ADR-0038](0038-aetherengine-sur-les-appareils-apple.md).

## Contexte

Rapporté sur une Apple TV, sans journal : « des fois quand je mets Play ou que je change la
qualité, ça reste bloqué en mode pause ». Deux causes, trouvées à la lecture du code.

1. **Le lecteur relisait du moteur ce qu'on lui avait demandé.** AetherEngine (comme ExoPlayer) ne
   dit `isPlaying` que lorsque l'image défile : `.loading`, `.seeking`, `.rebuffering` et `.stalled`
   donnent `false` (`StatusMapping.isPlaying`). `PlayerController.isPlaying` recopiait ce rapport,
   et tout en découlait : le sens de l'appui (`next = !isPlaying`), le bouton, « mets en pause si ça
   lit », la séance partagée. Pendant une bascule de qualité ou une recherche, l'écran montrait une
   pause que personne n'avait demandée, un appui envoyait « lecture » à qui voulait arrêter et le
   suivant « pause » à qui voulait lire. Une source se rouvrait toujours avec `play: true`, même
   derrière une pause.
2. **Le plugin ne reconstruisait jamais une session démontée.** Sur tvOS, AetherEngine libère son
   item AVPlayer et sa boucle locale à chaque passage en arrière-plan (économiseur d'écran derrière
   une pause, bouton TV, veille), se met en `.paused` et attend de l'hôte un
   `reloadAtCurrentPosition()` au retour (`needsForegroundVideoRestore`). Sans lui, `play()` passait
   l'état à `.playing` sur un lecteur sans item : la phase restait `.loading` pour toujours, et
   chaque appui alternait entre un sablier et une pause.

## Décision

1. **`PlaybackIntent` retient la dernière demande** (lire, ou rester en pause). Seules les demandes
   la changent : `togglePlayPause()`, `play()`, `pause()` du contrôleur. Aucun rapport du moteur ne
   la modifie.
2. **Un appui se lit ainsi** (`PlaybackIntent.toggle`) : moteur qui lit, pause ; moteur au repos,
   lecture ; moteur qui attend (charge, cherche, remplit son tampon), l'inverse de la dernière
   demande. Le moteur n'est donc cru que lorsqu'il est stable.
3. **L'écran et ses hooks lisent `wantsPlay`**, plus `isPlaying` : bouton, masquage du chrome,
   écran de pause, séance partagée, « reprendre ici ». `isPlaying` reste ce que le moteur rapporte,
   pour les mesures seulement (première image, qualité Auto).
4. **Une source se rouvre dans l'état demandé** : `session.open(..., play: wantsPlay)` pour le
   changement de qualité, la recherche hors de la session HLS et la reprise après une coupure.
5. **Une pause voulue par le lecteur est toujours portée au moteur** (minuterie, autre appareil,
   question sans réponse, TV éteinte), même s'il ne lit pas à cet instant.
6. **`AetherPlayer` reconstruit la session démontée** avant un `play()` ou un `seek`, au premier
   plan seulement, en retenant le play/pause demandé comme pendant une ouverture.

### Écarté

- **Adopter la pause quand le moteur la rapporte « stable ».** L'interface du moteur ne distingue
  pas une pause d'un moteur à l'arrêt ou tombé : une coupure de flux aurait rouvert en pause.
- **Reconstruire dès le retour au premier plan.** Il faudrait suivre le cycle de vie de l'app dans
  le plugin, du Swift de plus que personne ne compile ici, et rouvrir le flux pour quelqu'un qui
  n'a peut-être rien demandé. La reconstruction attend donc un geste : lecture ou recherche.

## Conséquences

- Changer de qualité, de piste ou chercher loin derrière une pause laisse le film en pause, sur
  tous les moteurs. Avant, il repartait seul.
- Une pause venue du système sans passer par l'app (appel, sortie audio perdue) laisse le bouton
  sur « pause » ; un appui relance, comme avant.
- Au retour sur l'Apple TV, l'image reste noire jusqu'à l'appui sur lecture ou une recherche, puis
  le film reprend à sa position. Le plugin tient la position rapportée pendant la reconstruction
  (le moteur remet son horloge à zéro) : sans cela, une reconstruction qui échoue faisait rouvrir
  le film à la seconde zéro. Elle peut encore lire zéro un court instant juste après.
- Une reconstruction qui échoue (ticket de lecture périmé après une longue veille) remonte comme
  une panne de source, que `StreamCutRecovery` rattrape en rouvrant avec un ticket neuf.
- La qualité Auto lit toujours `isPlaying` : son comportement ne change pas ici.
- Épinglé par `app/test/playback_intent_test.dart` (la règle, le contrôleur sur un moteur factice,
  et deux gardes sur le code) et `app/test/onyx_player_apple_sources_test.dart` (la reconstruction,
  faute de pouvoir exécuter du Swift).
