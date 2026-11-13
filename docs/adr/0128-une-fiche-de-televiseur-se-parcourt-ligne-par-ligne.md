# ADR-0128 — Une fiche de téléviseur se parcourt ligne par ligne et se pose section par section

- **Statut :** accepté, écrit sous Linux. Vérifié au banc sur les vrais écrans (film, série, demande), à
  l'échelle d'un téléviseur, sur les deux systèmes de navigation, captures à l'appui ; **rien n'a été
  essayé sur une vraie Apple TV**. Les réglages (460 ms, 36 px, 72 %) sont des estimations à confirmer
  au prochain essai (voir « À régler sur l'appareil »).
- **Date :** 2026-11-13
- **Portée :** `tv/nav/tv_sections.dart` (`TvSections`, `TvSection`, `TvSectionsPolicy`),
  `tv/nav/tv_rows.dart` (`TvRows`), `tv/nav/tv_sections_scroll.dart` (`TvSectionsScroll`),
  `tv/nav/tv_entry_focus.dart` (`TvEntryFocus`), `tv/tv_page.dart` (`TvPage`, `TvPageScope`),
  `tv/tv_touchpad_pace.dart` (`TvTouchpadStop`), `tv/tv_touchpad.dart`, `tv/tv_focus.dart`,
  `tv/tv_focus_scroll.dart`, `tv/nav/tv_dpad_focusable.dart`, `theme/app_motion.dart`
  (`AppMotion.section`, `sectionCurve`), `widgets/global/detail_actions.dart`,
  `widgets/global/detail_cast_section.dart`, `screens/requests/widgets/request_detail_actions.dart`,
  `request_season_list.dart`. Les quatre fiches : `movie_detail_screen`, `show_detail_screen`,
  `season_detail_screen`, `request_detail_screen`.
- **Amende**, pour les fiches seulement, l'[ADR-0122](0122-le-pave-va-posement-sur-les-commandes.md) et
  le point 4 de l'[ADR-0125](0125-la-bibliotheque-d-un-televiseur-pose-la-fiche-a-gauche-et-la-grille-a-droite.md)
  (voir « Ce que cela contredit »). **Prolonge**
  l'[ADR-0113](0113-changer-de-rangee-ramene-a-sa-premiere-carte.md),
  l'[ADR-0109](0109-le-focus-tv-entre-une-fois-ou-la-zone-le-decide.md) (un seul focus demandé par
  flèche, sur la bonne cible) et l'[ADR-0110](0110-un-seul-systeme-de-focus-dpad.md), dont elle
  respecte la règle : les écrans n'emploient que `TvFocusable` et `TvRegion`. `TvSections` existait
  depuis le 2026-11-10 sans ADR : celle-ci en fixe les règles.

## Contexte

Retour de l'utilisateur après la version 1.1.51 sur son Apple TV : « le problème de navigation dans
les médias n'est toujours pas résolu, il a même empiré. Quand je descends dans un média c'est un peu
rapide, j'aimerais que tu ralentisses ça quand je descends entre Lecture et la distribution. Quand je
suis dans le média et que je descends et remonte, j'ai beaucoup de mal à aller sur Lecture, c'est un peu
désorganisé. »

Les vrais écrans montés au banc, à 1280 px de mise en page comme sur l'appareil, donnent trois causes.

**1. Le parcours devinait sa cible dans tout l'écran.** `TvSections` ordonnait les sections entre
elles, mais laissait le parcours géométrique décider *dans* une section, et il préfère la cible la mieux
alignée, où qu'elle soit :

- depuis le bouton retour, calé à gauche, Bas sautait le synopsis, « Lecture » et la distribution pour
  le bandeau de la saga, pleine largeur, deux sections plus bas ;
- une section rendait en remontant sa *dernière cible quittée*. Une fois passé par le bouton retour,
  Haut y ramenait toujours : « Lecture » n'était plus atteignable, ni par Haut, ni par Bas, ni par
  Droite. Il fallait quitter la fiche ;
- sous « Lecture », le premier cran était la flèche « Acteur précédent », 34 px, puis une carte prise
  au milieu de l'éventail ;
- la fiche d'une série pouvait s'ouvrir sur le bouton retour : sa pastille de lecture attend l'épisode
  à reprendre, et arrivait alors dans une page qui avait déjà son focus.

**2. Chaque cible se ramenait à l'écran à sa façon.** Une affiche se centrait, une pastille se collait
en bas de l'écran, une ligne d'épisode se posait au tiers. En remontant d'un épisode aux saisons puis à
« Lecture », la page allait à 593 px, 0, 236, puis 0. Et ces trajets, souvent plus d'un demi-écran,
duraient 200 ms.

**3. Le pavé comptait ses crans comme dans un menu.** « Lecture » et les bulles de saisons font moins
de 64 px : ce sont des commandes, deux ou trois crans par glissé (ADR-0122). Le même glissé rejoué au
banc, avant et après :

| Geste | Avant | Après |
|---|---|---|
| glissé ordinaire depuis « Lecture » (film) | une carte au milieu de l'éventail, deux crans | la distribution, sa première carte |
| coup sec vers le haut depuis les titres similaires | le bouton retour, trois sections plus haut | la saga, une section |
| coup de pouce vers le bas depuis le bouton retour | la saga, par-dessus « Lecture » | la ligne du dessous : le synopsis s'il est coupé, sinon « Lecture » |
| long glissé depuis le dernier épisode (série) | les titres similaires, par-dessus la distribution | la distribution |

## Décision

**Une fiche est une page qui tient elle-même son parcours vertical et son défilement** (`TvPage`). Les
écrans ne changent pas : `TvRegion.sections` autour de la page, un `TvRegion.section` par bloc.

### 1. Haut et Bas suivent les lignes

`TvSections` décide seul de Haut et Bas, pour toute cible de la fiche (`TvSectionsState.targetFor`) :

- **dans une section, la ligne voisine** (`TvRows`). Les cibles d'une section forment des lignes : deux
  cibles sont sur la même ligne quand le milieu de l'une tombe dans la hauteur de l'autre. Aucun seuil
  en pixels, la page d'un téléviseur étant mise à l'échelle ;
- **au bout de la section, la section voisine** dans l'ordre de l'écran : sa première ligne en
  descendant, sa dernière en montant. Une section sans cible se franchit ;
- **on entre dans une ligne par son entrée** : la cible marquée `TvFocusable.entry` (la saison
  affichée) ou celle que la page focalise à l'ouverture (`autofocus` : « Lecture », « Demander »).
  Sans entrée, par la cible à la verticale de celle qu'on quitte, sinon par le début de la ligne. Les
  rangées gardent leur règle : la première carte (ADR-0113), ou la bulle quittée pour les saisons.

Remonter dans l'en-tête mène donc toujours à « Lecture », quelle que soit l'action ou le bouton quitté.
Une section n'a plus de mémoire à elle.

Gauche et droite gardent leur parcours, qui ne quitte pas la ligne.

### 2. Chaque ligne a une place, la même d'où qu'on vienne

`TvSectionsScroll` pose la page ; l'ancien `TvFocusable`, `TvFocusScroll` et `TvDpadFocusable` lui
laissent la main dans une fiche (`TvPageScope`). La place ne dépend que de la ligne focalisée :

- **la section se cale en haut de l'écran**, à 36 px du bord, titre compris. Toutes les lignes qu'elle
  montre alors partagent cette place : des bulles de saisons à « Marquer la saison vue », rien ne
  défile. L'en-tête, première section, pose la page tout en haut ;
- **une ligne trop basse pour cette place** fait monter la page juste assez pour se tenir à 72 % de la
  hauteur de l'écran. Une liste d'épisodes ne défile donc pas pour ses trois premières lignes, puis
  d'une ligne à chaque pas, la suivante visible dessous.

La place se calcule par les positions de défilement du viewport, pas par les rectangles à l'écran : une
section encore sous l'écran n'a pas de place fiable tant qu'elle n'est pas dessinée.

### 3. L'allure suit la distance

Un trajet prend de 200 ms (`AppMotion.standard`) à 460 ms (`AppMotion.section`), en proportion de sa
longueur, la durée longue étant atteinte à 60 % de la hauteur de l'écran. Un épisode de plus dans une
liste (135 px) prend 280 ms ; de « Lecture » à la distribution, 460 ms au lieu de 200. La courbe part
et se pose en douceur (`AppMotion.sectionCurve`, ease-in-out) : un ease-out lançait tout l'écran à
pleine vitesse dès la première image. Flèche maintenue : la durée courte, comme partout
(`AppMotion.track`). Mode léger et « réduire les animations » : la page saute, comme avant.

### 4. Le pavé de l'Apple TV s'arrête à chaque étape

Chaque section est une étape (`TvTouchpadStop`). `TvTouchpad` demande à la page où mène le pas avant de
le faire, ce qui vaut aussi sous dpad, où le focus ne se pose qu'à la microtâche suivante :

- **le pas vertical qui change de section est le dernier de son geste**, quelle que soit sa force : ni
  autre pas, ni cran dû, ni élan ;
- **dans une section, les commandes vont cran par cran** (bulles de saisons, « Marquer la saison vue »,
  bouton retour) ;
- **seules des cartes qui se suivent se parcourent d'un trait** : les épisodes d'une saison. Le geste
  s'arrête à la dernière carte ; l'en-tête de la liste ou la section suivante demandent le leur.

**Un geste finit quand le doigt se lève ou s'arrête.** Un doigt resté posé 200 ms sans bouger, puis
qui repart, commence un autre geste : descendre une fiche d'un glissé lent et continu ne bloque pas le
focus à la première étape.

Une flèche du pavé directionnel vaut toujours un pas, et une flèche maintenue traverse la fiche.

### 5. L'action principale reprend le focus quand elle arrive tard

`TvEntryFocus.claim` rend le focus à « Lecture » ou « Demander » quand la pastille naît après
l'ouverture (`DetailActions`, `RequestDetailActions`) : seulement s'il est resté nulle part, ou dans la
section de la pastille, là où le garde-fou l'avait posé faute de mieux. Qui est déjà descendu dans la
page, ou a ouvert un dialogue, garde sa place.

### 6. Les flèches de la distribution quittent l'écran du téléviseur

Gauche et droite passent déjà d'une carte à l'autre. Les deux flèches « Acteur précédent » et « Acteur
suivant » étaient deux crans de plus entre « Lecture » et l'éventail ; elles restent hors téléviseur.

## Ce que cela contredit

- **ADR-0122** (« deux ou trois crans par glissé sur les commandes ») : sur une fiche, une commande
  vaut un cran par geste. La demande d'alors portait sur les menus et la barre d'onglets, qui gardent
  leur réglage ; sur une fiche, chaque cran déplace la page d'un demi-écran.
- **ADR-0125, point 4** (« un pas vers le haut ou le bas défile en 200 ms, partout ») : sur une fiche,
  la durée suit la distance, jusqu'à 460 ms. L'accueil et les grilles gardent 200 ms.

Et une règle de `TvSections` qui n'était écrite nulle part : une section rendait en remontant sa
dernière cible quittée. Cette mémoire disparaît ; c'est elle qui ramenait au bouton retour.

## Écarté

- **Retirer le bouton retour du parcours de la télécommande**, comme le lecteur l'a fait (ADR-0124).
  Avec des lignes ordonnées, il n'est plus un piège : c'est la ligne au-dessus de « Lecture », à un
  geste. Le retirer est une décision de design que personne n'a demandée.
- **Une section par ligne** (trois sections emboîtées dans l'en-tête). La place d'une ligne se cale sur
  le début de sa section : « Lecture » aurait fait monter la page de 350 px.
- **Corriger le parcours géométrique** (élargir le faisceau, pondérer la distance). C'est la cause :
  aucun réglage ne fait à la fois passer Bas par des actions calées à droite et des bulles calées à
  gauche.
- **Centrer chaque ligne focalisée**, ou la poser à hauteur fixe. Les lignes d'une courte section
  feraient défiler la page à chaque pas, et l'en-tête ne resterait pas entier.
- **Un cran par geste partout sur la fiche.** Une saison de vingt épisodes demanderait vingt glissés.
- **Faire écouter le focus par la page** pour défiler à chaque changement. Deux défilements par pas
  reviendraient (ADR-0039) : les cibles gardent leur appel, et le cèdent à la page.
- **Ralentir tout défilement vertical.** L'accueil et la bibliothèque viennent d'être réglés à 200 ms
  (ADR-0125) et personne ne s'en plaint.

## Conséquences

- **Les deux systèmes de navigation tiennent la même carte.** Sous dpad, Haut et Bas d'un
  `TvFocusable` de fiche vont à la page avant sa zone (`DpadFocusable.onDirection`) : dpad cherche
  d'abord dans la zone, et un éventail de cartes penchées y trouvait toujours une voisine « plus bas »,
  d'où l'on ne sortait pas. `autoScroll` y est coupé dans une fiche. La page s'appuie sur
  `DpadRegionState.resolveEnter`, `@internal` dans dpad 3.3.0 comme pour `TvRailRegion` : à relire à
  chaque montée de version.
- **Android TV et le web des téléviseurs LG** prennent le parcours et les places. Le rythme du pavé ne
  concerne que la Siri Remote.
- **Hors téléviseur**, le clavier d'un bureau suit les mêmes lignes ; le défilement reste celui de
  Flutter.
- **Une fiche ajoutée demain** n'a rien à écrire : `TvRegion.sections` et ses sections suffisent. Une
  cible posée hors de toute section n'est plus atteinte par Haut et Bas.
- **Le contenu sans cible sous la dernière ligne** (les informations techniques d'un film) se lit comme
  avant : Bas, quand il n'y a plus rien à focaliser, fait défiler d'un demi-écran
  (`TvFocusScroll.scrollPast`).
- Épinglé par `test/tv_detail_pages_test.dart` et `test/tv_detail_touchpad_test.dart` (les vrais
  écrans, les deux systèmes), `test/tv_sections_test.dart`, `test/tv_sections_scroll_test.dart`
  (places, durées, courbe, avec les animations), `test/tv_entry_focus_test.dart` et
  `test/request_detail_navigation_map_test.dart`.

## À régler sur l'appareil

Tout est dans `TvSectionsScroll` et `AppMotion` :

| Réglage | Valeur | Si, à l'essai… |
|---|---|---|
| `AppMotion.section` | 460 ms | « encore trop rapide » : 520 à 600. « Ça traîne » : 380. |
| `AppMotion.sectionCurve` | ease-in-out | « ça met du temps à partir » : `Curves.easeOutCubic`. |
| `TvSectionsScroll.topMargin` | 36 px | le titre d'une section colle au bord : 48 à 60. |
| `TvSectionsScroll.focusBottom` | 0,72 | la ligne focalisée d'une liste paraît trop basse : 0,6. |
| `TvSectionsScroll.fullTravel` | 0,6 | un pas d'épisode paraît lent : 0,8 (durée longue plus rare). |
| `TvTouchpad._restBetweenGestures` | 200 ms | il faut lever le doigt pour refaire un pas : 150. Un glissé lent franchit deux étapes : 300. |

Sur une Apple TV HD, le mode léger (ADR-0086) retire le mouvement géométrique : la page saute à sa
place, sans durée. Le parcours et le rythme du pavé y valent comme ailleurs.
