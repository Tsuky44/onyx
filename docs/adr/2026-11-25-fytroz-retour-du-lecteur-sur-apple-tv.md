# Sur un téléviseur, la touche Retour quitte le lecteur

- **Statut :** accepté. Testé en Dart (analyse propre, 2992 tests) ; **pas encore vu sur une Apple
  TV**. La cause est déduite du code et du changement de moteur, pas mesurée sur l'appareil.
- **Date :** 2026-11-25
- **Portée :** `app/lib/screens/player/player_key_routing.dart` (`playerBackKeyEnd`),
  `player_screen_remote.dart` (cas `PlayerKeyBack`), `app/lib/tv/nav/tv_back.dart` (commentaire du
  constat C1), `app/test/support/player_remote_bench.dart`, `app/test/player_key_routing_test.dart`.
- **Complète** l'[ADR-0110](0110-un-seul-systeme-de-focus-dpad.md) sur son constat C1.

## Contexte

Signalé le 2026-11-25 sur une Apple TV, en 1.2.2 : le bouton Retour de la télécommande ne fait plus
rien dans le lecteur. Il marche dans les pages. Le code de l'app est identique en 1.2.1 et en
1.2.2 ; entre la 1.2.0 et la 1.2.1, Flutter est passé de 3.44 à 3.50.1, et flutter-tvos de
`1.5.1` à `1.12.2`.

Le Retour d'un téléviseur a deux entrées, que `TvBack` réconcilie : le `popRoute` du système et la
touche (Échap, `goBack`). Le constat C1 disait que l'Apple TV n'envoyait Menu qu'en `popRoute`.

Les pages traitent les deux entrées de la même façon (`TvBack.handle`). Le lecteur a son propre
gestionnaire de touches, qui défait sa pile (invitation, menus, volet, épisode suivant, barre de
contrôle) puis, en dernier, **sortait du plein écran**, ce qui ne fait rien sur un téléviseur. La
touche était marquée comme lue (`TvBack.claimKey`) : un `popRoute` arrivé dans les 300 ms était
absorbé comme la seconde moitié du même appui, et une touche traitée n'est de toute façon suivie
d'aucun `popRoute`. Tant que Menu n'arrivait qu'en `popRoute`, ce dernier pas n'était jamais
atteint sur Apple TV. Le banc de test du lecteur (`PlayerRemoteBench`), lui, quittait le lecteur :
c'est cet écart qui a laissé passer la régression.

## Décision

1. **La fin de la touche Retour est une règle nommée** (`playerBackKeyEnd`) : sur un téléviseur,
   quitter le lecteur, comme le `popRoute` ; sur un ordinateur, sortir du plein écran, Échap ne
   quittant pas le film.
2. **Le lecteur et son banc de test lisent la même règle**, au lieu que le banc en porte une copie.
3. Le commentaire du constat C1 dans `tv_back.dart` dit ce qu'on sait désormais.

Un appui qui arrive en touche puis en `popRoute`, ou l'inverse, reste un seul appui : `claimKey` et
`TvBack` absorbent la seconde moitié, et `PlayerExit` ne quitte qu'une fois.

## Conséquences

- Apple TV : Retour quitte le lecteur, que Menu arrive en touche, en `popRoute` ou les deux.
- Android TV : `goBack` passe toujours par le système ; Échap ou B d'une manette quittent désormais
  le lecteur au lieu de ne rien faire.
- Téléviseur LG (Retour réécrit en Échap) : même effet que sur Apple TV.
- Ordinateur : inchangé.

## À vérifier sur une Apple TV

1. Retour pendant la lecture, chrome masqué : le lecteur se ferme, et un seul écran se dépile.
2. Retour avec un menu ou le volet ouvert : il se referme d'abord, le lecteur reste ouvert.
3. Retour sur la barre de contrôle : la barre disparaît, le film continue.

Épinglé par `app/test/player_key_routing_test.dart` et `app/test/player_chrome_navigation_map_test.dart`.
