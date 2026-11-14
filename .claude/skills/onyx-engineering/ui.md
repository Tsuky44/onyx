# Interface

La direction s'appelle **Quiet Premium** : une scène charbon OLED, un accent bleu utilisé avec parcimonie, un mouvement bref. L'image du média porte l'émotion, le chrome s'efface.

## Sources de vérité

- `PROJECT_DESIGN.md` est le contrat visuel en vigueur : palette, typographie, composants, mouvement (§10), à faire et à éviter (§11). Lis la section du composant que tu touches.
- `PRODUCT.md` porte les principes produit et l'accessibilité.
- `design.md` est l'ancien brief « Cinematic Glass ». Il sert de référence, et `PROJECT_DESIGN.md` l'emporte en cas de désaccord.
- Le lecteur n'a qu'un chrome, le Chrome Onyx (`screens/player/widgets/onyx/`, ADR-0048).
- Ce que le lecteur pose sur le film à la demande est du verre (ADR-0130) : un menu, une fenêtre de question, le volet des onglets passent par `OnyxGlassPanel`, leurs boutons par `OnyxCapsuleButton`, une question par `PlayerQuestionWindow`. Le fond se lit sans flou (mode léger, téléviseurs LG) ; le chrome au repos n'en a pas. Les couleurs du verre sont dans `OnyxChromeTheme`.
- Les menus du lecteur ont un seul dessin en deux tailles (`OnyxMenuStyle`) : sur téléviseur un menu par réglage (`OnyxSettingsMenu.standalone`), ailleurs l'index de la roue crantée. Un réglage de plus est une `OnyxMenuSection`, pas un nouveau menu.
- Les onglets du lecteur (Infos, Épisodes, Chapitres, Regarder ensemble, Stats) ont une liste (`_tabEntries`, dans `player_screen_overlays.dart`) et deux présentations : le volet sous la barre d'un téléviseur (`OnyxTvTabs`) et la feuille du bas des autres écrans (`PlayerTabSheet`). Un contenu d'onglet est un widget de `screens/player/widgets/tabs/`, écrit pour les deux : ses rangées passent par `OnyxControlsRow`.
- Pour le savoir-faire UI approfondi (critique, polish, audit, animation, accessibilité), lis `.agents/skills/impeccable/SKILL.md` et `.agents/skills/tasteful-ui/SKILL.md` par leur chemin. Les liens de `.claude/skills/` vers ces dossiers sont cassés sous Windows.

## Tokens

- Couleurs : `AppColors` (`theme/app_colors.dart`). Mouvement : `AppMotion` (`theme/app_motion.dart`). Thème : `AppTheme`.
- Le nouveau code n'écrit ni `Color(0x…)` ni `Duration(milliseconds: …)` d'animation. Il reste ~110 couleurs brutes et ~110 durées brutes : convertis celles des lignes que tu touches.
- Une valeur qui manque s'ajoute au fichier de tokens, avec un commentaire sur son rôle, avant d'être utilisée.
- Mouvement : durées de 180 à 280 ms (`micro`, `standard`, `emphasis`) et une seule courbe, `AppMotion.curve`. `AppMotion.fade(context)` sert à l'opacité et aux couleurs (conservé sous « réduire les animations »). `AppMotion.move(context)` sert à tout ce qui est géométrique (ramené à zéro).
- Le lancement d'une lecture depuis « Reprendre » est un zoom simple. La page du lecteur ne subit jamais de transformation (rideau abandonné).

## Composants imposés

| Besoin | Utilise | Pourquoi |
|---|---|---|
| Curseur | `AppSlider` | Le `Slider` de Material fige l'arbre d'accessibilité sous Windows (ADR-0024). |
| Champ de saisie | enveloppé par `TvDeferredKeyboard` | Sur TV, le clavier plein écran piège le focus. Imposé par `no_bare_text_field_test.dart`. |
| Image réseau | `AppNetworkImage` + `utils/poster_url.dart` | Décodage à la taille affichée et cache partagé. |
| Chargement, vide, erreur | `LoadingView`, `EmptyStateView`, `ErrorStateView` | Un seul langage pour les trois états. |
| Page de réglages | `SettingsPage`, `SettingsGroup`, `SettingsTile`… (`settings/widgets/settings_ui.dart`) | Une mise en page et une densité cohérentes. |
| Mise en page, grilles | `Responsive` (`utils/responsive.dart`) | Points de rupture, marges, colonnes d'affiches et taille tactile minimale. |
| Verre, chrome | `glass_chrome.dart` | Un seul rendu de verre. |
| Titre que le serveur n'a pas | affiche voilée (`PosterCard.dimmed`) et `UnavailableBadge` ; dans une recherche, le rangement de `SearchShelves` | Un seul signe pour « pas là » partout : titres similaires, listes, recherche (ADR-0129). |

Avant de créer un composant, cherche dans `widgets/global/` et dans les `widgets/` de l'écran voisin. Un composant utilisé par un deuxième écran monte dans `widgets/global/`.

## TV et télécommande

Chaque écran atteignable sur TV se pilote entièrement au D-pad.

- Activer : `kTvSelectKeys`. Revenir : `kTvBackKeys`. Tous deux sont dans `tv/tv_focus.dart`, jamais réécrits par widget.
- Le focus est toujours visible (ADR-0008), il est mémorisé par ligne au retour sur l'écran (`tv_focus_memory.dart`, `tv_focus_rows.dart`), et le premier élément utile le reçoit à l'ouverture.
- L'échelle vient de `tv_ui_scale.dart`, et la répétition des touches de `tv_key_repeat.dart`.
- Un seul défilement par pas de focus, celui de `TvFocusScroll` (ou de `TvFocusable`) : n'appelle pas `Scrollable.ensureVisible` à côté. Sur Apple TV, la force d'un glissé passe par `TvTouchpad.boostFor` (ADR-0039).
- Une fiche (film, série, saison, demande) est un `TvRegion.sections` autour de la page et un `TvRegion.section` par bloc (ADR-0128) : Haut et Bas y suivent les lignes sans en sauter, chaque ligne pose la page à une seule place (`TvSectionsScroll`) et le pavé de l'Apple TV s'y arrête à chaque section. Une cible posée hors de toute section n'est plus atteinte par Haut et Bas. L'action principale porte `autofocus` : c'est l'entrée de sa ligne, et `TvEntryFocus.claim` lui rend le focus quand elle arrive après l'ouverture.
- Sur l'Apple TV, la recherche est l'écran du système, natif (ADR-0129) : `TvSystemSearchScreen` ne dessine rien et dit à l'hôte quoi montrer par `TvSystemSearch`. Ce qui s'affiche dans une recherche se change donc à trois endroits : `SearchShelves` pour le contenu, `TvSearchScreen` et `SearchResultsScreen` pour Flutter, `tvos/Runner/SystemSearch*.swift` pour l'Apple TV.
- Le lecteur à la télécommande suit ADR-0006. Tout ce qu'il pose sur l'image d'un téléviseur passe par `PlayerTvScale.layer` (mis en page sur 1280, comme les pages) : une couche oubliée se dessine à la taille brute de l'écran, minuscule sur une Apple TV et double sur un téléviseur Android.
- Refonte en cours vers un seul système de focus, dpad (ADR-0110, `docs/refonte-navigation-dpad.md`) : n'ajoute ni `FocusTraversalGroup`, ni politique de parcours, ni `Shortcuts`, ni `onKeyEvent`, ni gestionnaire global de touches, ni widget de l'ancien système (`TvFocusMemory`, `TvFocusPanes`…). Les écrans n'emploient que `TvFocusable` (action en `onSelect`) et `TvRegion` ; dpad ne s'importe que dans `lib/tv/`. Gardé par `test/no_parallel_focus_system_test.dart`.
- Un écran TV nouveau ou modifié reçoit un test de focus sur le modèle de `tv_focus_test.dart` ou `onyx_settings_menu_tv_test.dart`.

## Qualité d'écran

- **Trois états** pour toute donnée asynchrone : chargement, vide et erreur avec une action pour réessayer. Les données en cache s'affichent pendant la revalidation.
- **Poids de l'arbre** (ADR-0025) : garde de la légèreté sous Windows. Utilise des constructeurs `.builder` pour les listes longues, un `const` partout où c'est possible, et découpe en petits widgets pour que chaque `setState` ou `notifyListeners` ne reconstruise que ce qui change.
- **Accessibilité** : un bouton-icône porte un `tooltip` ou un label `Semantics`, et les cibles tactiles respectent `Responsive.minTouchTarget`. Le texte suit la hiérarchie de `PROJECT_DESIGN.md` §7.
- **Textes** : français, en phrases, courts. Un message d'erreur dit ce qui s'est passé et quoi faire. Tout texte affiché passe par `tr('…')` (`l10n/tr.dart`) et gagne son entrée anglaise dans `l10n/en.dart` ; une valeur variable passe en argument (`tr('Saison {0}', [n])`), jamais en interpolation (ADR-0047, gardé par `l10n_coverage_test.dart`).
- **Vérification** : lance l'app, puis regarde l'écran en largeur téléphone et en largeur desktop, avec le focus TV si l'écran est concerné, et sous « réduire les animations » si tu as ajouté du mouvement. Pour une passe de finition, applique `.agents/skills/impeccable/reference/polish.md`.
