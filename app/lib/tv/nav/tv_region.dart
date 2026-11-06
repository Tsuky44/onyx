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
/// emploient. Sous un [OnyxDpad], la zone est une `DpadRegion` ; ailleurs,
/// elle délègue à l'ancien système (`TvFocusMemory`, `TvFocusPane`), à
/// l'identique. En phase 1 de la refonte, `OnyxDpad` n'est pas monté : toutes
/// les zones de l'app suivent donc encore l'ancien système.
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
/// « Mémoire » sans souvenir retombe sur l'élément marqué `entry`, puis sur
/// le plus proche (constat C8).
class TvRegion extends StatelessWidget {
  const TvRegion.rail({
    super.key,
    required this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.rail;

  const TvRegion.grid({
    super.key,
    required this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.grid;

  const TvRegion.list({
    super.key,
    required this.id,
    required this.child,
    this.entersAtTop = false,
  }) : kind = TvRegionKind.list;

  const TvRegion.tabs({
    super.key,
    required this.id,
    required this.child,
  })  : kind = TvRegionKind.tabs,
        entersAtTop = false;

  /// Un volet. Avec l'ancien système, il doit vivre sous un `TvFocusPanes`.
  const TvRegion.pane({
    super.key,
    required this.id,
    required this.child,
  })  : kind = TvRegionKind.pane,
        entersAtTop = false;

  final TvRegionKind kind;

  /// `"<écran>/<zone>"`, stable d'une visite à l'autre (`home/continue`,
  /// `settings/categories`). Sous dpad, c'est la clé de mémoire, rangée sous
  /// le profil qui navigue (voir [OnyxDpad.memoryKeyFor]).
  final String id;

  final Widget child;

  /// À la première visite, le focus entre sur le premier élément visible de
  /// la zone plutôt que sur le plus proche de celui qu'on quitte (le
  /// `TvFocusMemory.entersAtTop` de l'ancien système). Sous dpad, c'est
  /// l'élément marqué `entry` qui joue ce rôle.
  final bool entersAtTop;

  @override
  Widget build(BuildContext context) {
    if (!TvNavScope.isActive(context)) return _legacy();
    return DpadRegion(
      memoryKey: OnyxDpad.memoryKeyFor(context, id),
      debugLabel: id,
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
