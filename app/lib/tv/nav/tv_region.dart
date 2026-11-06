import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

import '../tv_focus_memory.dart';
import '../tv_focus_panes.dart';
import 'onyx_dpad.dart';

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
/// | [pane] | mémoire | sort (vers le volet voisin) | sort |
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
  }) : kind = TvRegionKind.rail;

  const TvRegion.grid({
    super.key,
    this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.grid;

  const TvRegion.list({
    super.key,
    this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.list;

  const TvRegion.tabs({super.key, this.id, required this.child})
      : kind = TvRegionKind.tabs,
        entersAtTop = false;

  /// Un volet. Avec l'ancien système, il doit vivre sous un `TvFocusPanes`.
  const TvRegion.pane({super.key, this.id, required this.child})
      : kind = TvRegionKind.pane,
        entersAtTop = false;

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
    return DpadRegion(
      memoryKey: id == null ? null : OnyxDpad.memoryKeyFor(context, id),
      debugLabel: id ?? kind.name,
      enter: kind == TvRegionKind.tabs
          ? DpadEnterBehavior.entry
          : DpadEnterBehavior.restore,
      horizontalEdge: switch (kind) {
        TvRegionKind.rail || TvRegionKind.tabs => DpadEdgeBehavior.stop,
        TvRegionKind.grid => DpadEdgeBehavior.lineWrap,
        TvRegionKind.list || TvRegionKind.pane => DpadEdgeBehavior.leave,
      },
      verticalEdge: DpadEdgeBehavior.leave,
      child: child,
    );
  }

  Widget _legacy() {
    switch (kind) {
      case TvRegionKind.rail:
      case TvRegionKind.grid:
      case TvRegionKind.list:
        return TvFocusMemory(entersAtTop: entersAtTop, child: child);
      case TvRegionKind.pane:
        return TvFocusPane(child: child);
      case TvRegionKind.tabs:
        // L'ancien en-tête choisit lui-même son onglet d'entrée
        // (`main_shell`, par `TvFocusEntries`) : rien à poser ici.
        return child;
    }
  }
}
