import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

import '../tv_focus_memory.dart';
import '../tv_focus_panes.dart';
import '../tv_focus_rows.dart';
import 'onyx_dpad.dart';
import 'tv_control_rows.dart';
import 'tv_pane_region.dart';
import 'tv_slide_edges.dart';

/// La forme d'une zone : elle fixe comment le focus y entre et en sort.
enum TvRegionKind {
  /// Une rangée horizontale d'affiches.
  rail,

  /// Une grille.
  grid,

  /// Une liste verticale.
  list,

  /// Les onglets d'un en-tête.
  tabs,

  /// Un volet d'un écran en plusieurs colonnes (les réglages).
  pane,

  /// Les volets posés côte à côte, autour de leurs [pane].
  panes,

  /// La page affichée d'un carrousel : gauche et droite au bord la tournent.
  slide,

  /// Une page entière, faite d'autres zones (le contenu d'un onglet).
  page,

  /// Une rangée de commandes du chrome du lecteur, sous un [controlRows].
  controls,

  /// Les rangées de commandes d'un chrome, autour de leurs [controls].
  controlRows,
}

/// Une zone que la télécommande parcourt comme un tout, et qui se souvient de
/// l'endroit où l'on était (ADR-0110).
///
/// C'est, avec `TvFocusable`, le seul widget de navigation que les écrans
/// emploient. Sous un [OnyxDpad] (compilation `ONYX_TV_NAV=dpad`), la zone est
/// une `DpadRegion` ; ailleurs, elle délègue à l'ancien système
/// (`TvFocusMemory`, `TvFocusPane`), à l'identique.
///
/// Sous dpad, chaque forme règle l'entrée et les bords :
///
/// | Forme | Entrée | Gauche/droite au bord | Haut/bas au bord |
/// |---|---|---|---|
/// | [rail] | mémoire | reste (ne saute pas à l'autre bout de l'écran) | sort |
/// | [grid] | mémoire | passe à la ligne | sort |
/// | [list] | mémoire | sort | sort |
/// | [tabs] | onglet marqué `entry` (l'onglet affiché) | reste | sort |
/// | [pane] | mémoire, sinon le premier élément (le plus haut) | sort (vers le volet voisin) | sort |
/// | [panes] | pas de zone : chaque volet est la sienne | — | — |
/// | [slide] | mémoire | tourne la page ([TvRegion.onEdge]) | sort |
/// | [page] | pas de zone sous dpad (voir [TvRegion.page]) | — | — |
/// | [controls] | `preferredFocus`, sinon le plus proche | reste | rangée voisine, dans l'ordre de l'écran |
/// | [controlRows] | pas de zone : chaque rangée est la sienne | — | — |
///
/// « Mémoire » sans souvenir retombe sur l'élément marqué `entry`
/// (`TvFocusable.entry`), puis sur le plus proche (constat C8).
///
/// Sous dpad, les zones ne s'emboîtent pas : un élément appartient à la zone
/// la plus proche au-dessus de lui, et c'est elle seule qui décide de l'entrée.
/// L'ancien système, lui, faisait parler la zone la plus extérieure d'abord
/// (un onglet avant sa rangée).
class TvRegion extends StatelessWidget {
  const TvRegion.rail({
    super.key,
    this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.rail,
       onEdge = null,
       preferredFocus = null,
       onNavigate = null;

  const TvRegion.grid({
    super.key,
    this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.grid,
       onEdge = null,
       preferredFocus = null,
       onNavigate = null;

  const TvRegion.list({
    super.key,
    this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.list,
       onEdge = null,
       preferredFocus = null,
       onNavigate = null;

  /// Une page entière, faite d'autres zones : le contenu d'un onglet, avec
  /// ses rangées.
  ///
  /// **Sous dpad, ce n'est pas une zone** : une `DpadRegion` cherche d'abord
  /// dans ses propres éléments avant d'en sortir, et les cartes des rangées
  /// appartiennent à leur rangée, pas à la page. Autour de l'accueil, Bas
  /// depuis le bouton du bandeau sautait donc la première rangée pour « Tout
  /// voir » de la suivante, le premier élément *de la page* en dessous (vu au
  /// simulateur, constat N6 du plan). L'entrée dans la page est alors celle de
  /// la zone où le focus arrive.
  ///
  /// Avec l'ancien système, c'est une mémoire qui entre en haut de la page à
  /// la première visite (`TvFocusMemory(entersAtTop: true)`), à l'identique.
  const TvRegion.page({super.key, this.id, required this.child})
    : kind = TvRegionKind.page,
      entersAtTop = true,
      onEdge = null,
      preferredFocus = null,
      onNavigate = null;

  const TvRegion.tabs({super.key, this.id, required this.child})
    : kind = TvRegionKind.tabs,
      entersAtTop = false,
      onEdge = null,
      preferredFocus = null,
      onNavigate = null;

  /// Un volet, sous un [TvRegion.panes].
  ///
  /// Gauche et droite passent toujours au volet voisin quand rien ne suit
  /// dans celui-ci, quelle que soit la hauteur de ce qu'on y trouve ; on y
  /// entre sur l'élément qu'on y avait quitté, sinon sur le premier, le plus
  /// haut (pas sur celui qui est à la même hauteur). Sous dpad, voir
  /// `TvPaneRegion` ; avec l'ancien système, `TvFocusPane`.
  const TvRegion.pane({super.key, this.id, required this.child})
    : kind = TvRegionKind.pane,
      entersAtTop = false,
      onEdge = null,
      preferredFocus = null,
      onNavigate = null;

  /// Des volets côte à côte (une liste de catégories et la page qu'elle
  /// ouvre), chacun dans son [TvRegion.pane].
  ///
  /// **Sous dpad, ce n'est pas une zone** : chaque volet est la sienne, et
  /// les zones ne s'emboîtent pas (constat C15). Avec l'ancien système, c'est
  /// le `TvFocusPanes` qui ordonne ses volets.
  const TvRegion.panes({super.key, required this.child})
    : kind = TvRegionKind.panes,
      id = null,
      entersAtTop = false,
      onEdge = null,
      preferredFocus = null,
      onNavigate = null;

  /// La page affichée d'un carrousel (le bandeau de l'accueil) : quand rien
  /// ne suit sur la ligne dans la page, gauche et droite appellent [onEdge],
  /// qui la tourne, au lieu de filer ailleurs sur l'écran.
  ///
  /// Une zone par page, posée **dans** la page : sous dpad, une zone bloquée
  /// au bord fait d'abord défiler ce qui défile entre le focus et elle, et
  /// autour du `PageView` ce serait lui, de 80 % de page. Sans [onEdge] (une
  /// seule page), gauche et droite sortent de la zone. Avec l'ancien
  /// système, voir `TvSlideEdges`.
  const TvRegion.slide({super.key, required this.child, this.onEdge})
    : kind = TvRegionKind.slide,
      id = null,
      entersAtTop = false,
      preferredFocus = null,
      onNavigate = null;

  /// Une rangée de commandes du chrome télé du lecteur, sous un
  /// [TvRegion.controlRows] : gauche et droite y restent et s'arrêtent à ses
  /// bords, Haut et Bas passent à la rangée voisine, dans l'ordre de
  /// l'écran. On y entre sur [preferredFocus] (la lecture, la barre), sinon
  /// sur l'élément le plus proche à l'horizontale.
  ///
  /// Sous dpad, voir `TvControlRowRegion` ; avec l'ancien système,
  /// `TvFocusRow`, à l'identique.
  const TvRegion.controls({super.key, required this.child, this.preferredFocus})
    : kind = TvRegionKind.controls,
      id = null,
      entersAtTop = false,
      onEdge = null,
      onNavigate = null;

  /// Les rangées de commandes d'un chrome, chacune dans son
  /// [TvRegion.controls].
  ///
  /// **Sous dpad, ce n'est pas une zone** (constat C15) : il ne fait que
  /// recenser ses rangées (`TvControlRows`). Avec l'ancien système, c'est
  /// `TvFocusRows`, qui appelle [onNavigate] à chaque pas qu'il fait. Sous
  /// dpad, [onNavigate] ne sert pas : chaque flèche traverse le lecteur avant
  /// dpad (constat C4), et le lecteur relance lui-même son compte à rebours.
  const TvRegion.controlRows({super.key, required this.child, this.onNavigate})
    : kind = TvRegionKind.controlRows,
      id = null,
      entersAtTop = false,
      onEdge = null,
      preferredFocus = null;

  final TvRegionKind kind;

  /// `"<écran>/<zone>"`, stable d'une visite à l'autre (`home/continue`,
  /// `settings/categories`). Sous dpad, c'est la clé de mémoire, rangée sous
  /// le profil qui navigue (voir [OnyxDpad.memoryKeyFor]) : la zone retrouve
  /// sa carte même reconstruite.
  ///
  /// Nul : la zone ne se souvient que tant qu'elle est montée, comme avec
  /// l'ancien système. C'est ce que veut une zone de fiche : la mémoire de dpad
  /// est retrouvée par position à l'écran (constat C7), et une clé partagée
  /// par toutes les fiches poserait le focus, dans le casting d'un film, à
  /// l'endroit où on l'avait laissé dans celui d'un autre.
  final String? id;

  final Widget child;

  /// À la première visite, le focus entre sur le premier élément visible de
  /// la zone plutôt que sur le plus proche de celui qu'on quitte (le
  /// `TvFocusMemory.entersAtTop` de l'ancien système). Sous dpad, toute zone
  /// entre par sa mémoire, et sans mémoire par l'élément marqué
  /// `TvFocusable.entry` (l'index 0 d'une rangée) : ce drapeau n'y change
  /// rien (constat C8).
  final bool entersAtTop;

  /// Gauche ou droite au bord d'une [TvRegion.slide].
  final ValueChanged<TraversalDirection>? onEdge;

  /// L'entrée d'une [TvRegion.controls].
  final FocusNode? preferredFocus;

  /// Voir [TvRegion.controlRows] : ancien système seulement.
  final VoidCallback? onNavigate;

  /// La clé d'un élément de zone qui se reconstruit sous le focus (une
  /// rangée de l'accueil rechargée au retour d'un film), sous dpad.
  ///
  /// La carte d'un autre média est alors une autre carte : son nœud n'hérite
  /// pas du focus ni de la mémoire de celle qui était là, et dpad, qui voit le
  /// nœud focalisé disparaître, pose le focus sur la carte arrivée au même
  /// endroit de l'écran (constat C7). Pas de `findChildIndexCallback` : le
  /// nœud suivrait sa carte déplacée hors de l'écran, et le focus avec lui.
  ///
  /// Nulle avec l'ancien système : son garde-fou, devant une carte détruite,
  /// renvoie le focus en haut de la page.
  static Key? itemKey(BuildContext context, Object id) =>
      TvNavScope.isActive(context) ? ValueKey<Object>(id) : null;

  @override
  Widget build(BuildContext context) {
    if (!TvNavScope.isActive(context)) return _legacy();
    final id = this.id;
    final memoryKey = id == null ? null : OnyxDpad.memoryKeyFor(context, id);
    switch (kind) {
      case TvRegionKind.page:
      case TvRegionKind.panes:
        return child;
      case TvRegionKind.controlRows:
        return TvControlRows(child: child);
      case TvRegionKind.controls:
        return TvControlRowRegion(
          preferredFocus: preferredFocus,
          debugLabel: kind.name,
          child: child,
        );
      case TvRegionKind.pane:
        return TvPaneRegion(
          memoryKey: memoryKey,
          debugLabel: id ?? kind.name,
          child: child,
        );
      case TvRegionKind.rail:
      case TvRegionKind.grid:
      case TvRegionKind.list:
      case TvRegionKind.tabs:
      case TvRegionKind.slide:
        break;
    }
    return DpadRegion(
      memoryKey: memoryKey,
      debugLabel: id ?? kind.name,
      enter: kind == TvRegionKind.tabs
          ? DpadEnterBehavior.entry
          : DpadEnterBehavior.restore,
      horizontalEdge: switch (kind) {
        TvRegionKind.rail || TvRegionKind.tabs => DpadEdgeBehavior.stop,
        TvRegionKind.slide =>
          onEdge == null ? DpadEdgeBehavior.leave : DpadEdgeBehavior.stop,
        TvRegionKind.grid => DpadEdgeBehavior.lineWrap,
        TvRegionKind.list ||
        TvRegionKind.pane ||
        TvRegionKind.panes ||
        TvRegionKind.page ||
        TvRegionKind.controls ||
        TvRegionKind.controlRows => DpadEdgeBehavior.leave,
      },
      verticalEdge: DpadEdgeBehavior.leave,
      onEdge: onEdge,
      child: child,
    );
  }

  Widget _legacy() {
    switch (kind) {
      case TvRegionKind.rail:
      case TvRegionKind.grid:
      case TvRegionKind.list:
      case TvRegionKind.page:
        return TvFocusMemory(entersAtTop: entersAtTop, child: child);
      case TvRegionKind.pane:
        return TvFocusPane(child: child);
      case TvRegionKind.panes:
        return TvFocusPanes(child: child);
      case TvRegionKind.slide:
        final onEdge = this.onEdge;
        return onEdge == null
            ? child
            : TvSlideEdges(onEdge: onEdge, child: child);
      case TvRegionKind.controls:
        return TvFocusRow(preferredFocus: preferredFocus, child: child);
      case TvRegionKind.controlRows:
        return TvFocusRows(onNavigate: onNavigate, child: child);
      case TvRegionKind.tabs:
        // L'ancien en-tête choisit lui-même son onglet d'entrée
        // (`main_shell`, par `TvFocusEntries`) : rien à poser ici.
        return child;
    }
  }
}
