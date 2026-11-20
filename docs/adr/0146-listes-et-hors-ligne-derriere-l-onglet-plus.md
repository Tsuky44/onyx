# ADR-0146 — Listes et Hors ligne derrière l'onglet « Plus » de la capsule

- **Statut :** accepté. Maquettes « Un bouton « Plus » pour Listes et Hors ligne » : la A choisie
  par l'utilisateur le 2026-11-18 (« ok parfait »), avec sa règle : « si on est dans listes et
  qu'on clique sur liste ça affiche le menu si y'a plus de 2 et sinon ça switch dans l'autre si
  y'en a deux ». Vérifié en test, **pas encore vu sur un iPhone**.
- **Date :** 2026-11-18
- **Portée :** `screens/shell/mobile_bottom_nav.dart` (l'onglet « Plus »),
  `screens/shell/phone_more_menu.dart` (nouveau : `PhoneMoreItem`, `PhoneMoreMenu`,
  `showPhoneMoreMenu`).
- **Prolonge** l'[ADR-0142](0142-la-barre-d-onglets-du-telephone-est-une-capsule-de-verre.md).

## Contexte

Avec deux bibliothèques, les demandes, les listes et le hors-ligne, la capsule du téléphone portait
six onglets d'environ 49 points : « Demandes » s'y coupait en « Demand… » sur l'iPhone. Trois
propositions : A, « Plus » en cinquième onglet ; B, un rond « ••• » à part, entre la capsule et la
recherche ; C, trois points au bout de la capsule, sans nom, sur 36 points de large.

## Décision

1. **Listes et Hors ligne se rangent derrière « Plus »** quand les deux existent. « Plus » est le
   dernier onglet de la capsule, avec les trois points et son nom ; les autres onglets passent à
   environ 58 points et « Demandes » tient en entier. Une seule des deux pages (pas de listes sur
   le serveur, ou pas de téléchargement sur l'appareil) garde son onglet à elle, comme avant.
2. **Le menu.** « Plus » touché ouvre un petit menu de verre au-dessus de la capsule, aligné sur
   son bord droit : une rangée par page, une coche sur celle qui est affichée. La page s'assombrit
   un peu, sauf la capsule et le rond de la recherche, qui restent nets ; la lentille glisse
   jusqu'à « Plus » le temps qu'il est ouvert. Toucher à côté ou Retour le referme sans changer de
   page.
3. **Sur l'une des pages du menu**, l'onglet prend son icône et son nom, avec la lentille : on sait
   où l'on est. Le toucher alors, avec deux pages derrière « Plus », passe directement à l'autre :
   un menu pour un seul choix serait un geste de trop. Avec plus de deux, il rouvre le menu.
4. **La visite guidée** pointe « Plus » pour l'étape Hors ligne, qui s'y trouve.

### Écarté

- **B, un rond à part** : trois pièces de verre en bas au lieu de deux, pour la même place gagnée.
- **C, trois points sans nom** : le plus de place pour les quatre autres, mais une cible de
  36 points de large, sous les 44 d'Apple, et un bouton sans nom qui se devine moins bien.

## Conséquences

- Hors ligne et Listes coûtent un toucher de plus depuis les autres onglets, aucun pour passer de
  l'une à l'autre.
- Épinglé par `test/phone_tab_bar_test.dart` (« Plus » et son menu, aligné sur la capsule, le choix
  qui change de page et renomme l'onglet, la bascule sans menu entre les deux pages, le toucher à
  côté, une seule page sans « Plus »).
