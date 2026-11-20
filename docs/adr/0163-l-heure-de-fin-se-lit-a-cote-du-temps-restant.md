# ADR-0163 — L'heure de fin se lit à côté du temps restant

- **Statut :** accepté. Demandé par l'utilisateur (2026-11-20) : « depuis la refonte des lecteurs,
  on n'a plus l'heure de fin d'un média ; je veux le temps restant et, juste à côté, l'heure à
  laquelle le média se termine si aucune pause n'est faite, sur tous les appareils ». Couvert par
  des tests de widget ; **pas encore vu sur un ordinateur, un téléphone ni un téléviseur**.
- **Date :** 2026-11-20
- **Portée :** `screens/player/widgets/onyx/onyx_controls_rows.dart` (`_buildTimes`),
  `onyx_pointer_chrome.dart`, `onyx_handheld_chrome.dart`, `l10n/en.dart` (clé existante
  `Fin à {0}`), `test/onyx_controls_layer_test.dart`, `test/onyx_handheld_chrome_test.dart`.
- **Contredit** l'[ADR-0139](0139-un-seul-arrangement-du-lecteur-sur-tous-les-ecrans.md) (point 4 :
  l'heure de fin au survol du temps restant ; « Écarté : garder l'heure de fin sous la barre »),
  l'[ADR-0136](0136-sur-un-ecran-tenu-en-main-le-lecteur-prend-l-arrangement-de-l-apple-tv.md)
  (« pas d'heure de fin », option « garder l'heure de fin » écartée) et le point de l'ADR-0124 qui
  gardait « le temps restant à droite, sans l'heure de fin ». Elles ont été écrites sur une maquette
  qui ne la montrait pas ; l'utilisateur la redemande, parce que savoir à quelle heure on aura fini
  est ce qu'il lit en premier en lançant un film.

## Contexte

Depuis la refonte du lecteur (ADR-0124, 0136, 0139) le chrome n'écrit plus que le temps écoulé et
le temps restant. L'heure de fin avait disparu des écrans tenus en main et des téléviseurs, et ne
survivait sur un ordinateur que dans une infobulle, invisible au toucher et à la télécommande.

## Décision

1. **Une seule rangée de temps pour les trois arrangements** (`_buildTimes`, qui remplace
   `_buildTvTimes` et `_buildPointerTimes`) : le temps écoulé à gauche ; à droite le temps restant
   (`-01:18:00`) puis, juste à côté, `Fin à 21:04` (`Ends at 21:04` en anglais), d'une teinte plus
   discrète.
2. **L'heure est celle de l'horloge de l'appareil, si la lecture ne s'arrête plus** :
   `formatEndClock(restant)`. La rangée est reconstruite à chaque position ; une pause laisse
   donc le restant fixe et l'heure avance avec l'horloge.
3. **L'infobulle au survol disparaît** : l'information est écrite, elle n'a plus besoin d'être
   demandée.
4. Pas de nouvelle chaîne : `Fin à {0}` avait déjà ses traductions FR/EN (l'écran de pause).

## Conséquences

- La rangée de temps ne gagne pas de hauteur ; elle est un peu plus large à droite. Les tests de
  largeur (téléphone le plus petit couché, tablette en écran partagé) la couvrent.
- Rien à changer côté serveur ni contrat d'API.
