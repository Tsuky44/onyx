import 'package:flutter/widgets.dart';

import '../input/tv_arrow_gate.dart';
import '../tv_focus.dart' show TvBackAction, TvBackIntent, tvRemoteShortcuts;
import 'onyx_dpad.dart';
import 'tv_back.dart';

/// Ce que `main.dart` pose autour de l'app quand elle navigue sur dpad
/// (`ONYX_TV_NAV=dpad`, ADR-0110). Le banc de test (`tv_nav_harness.dart`)
/// pose la même chose, d'ici, pour qu'un test et l'app ne divergent pas.
///
/// Trois étages, dans cet ordre de haut en bas :
///
/// 1. [aboveApp] : [TvBack], **au-dessus** de `MaterialApp`. Flutter consulte
///    les observateurs de `popRoute` dans l'ordre d'inscription, et celui de
///    `WidgetsApp` dépile sans rien demander : posé plus bas, [TvBack] ne
///    verrait Menu qu'à la racine ;
/// 2. [shortcuts] et [actions] de `MaterialApp`, sans rien de directionnel :
///    les flèches sont à dpad. Restent OK (`select`, A d'une manette) pour les
///    boutons Material que rien n'enveloppe, et Retour pour ce que [TvBack]
///    rend au reste de l'app (voir [actions]) ;
/// 3. [belowApp] : [OnyxDpad] dans `MaterialApp.builder`, et [TvArrowGate]
///    juste sous lui, le seul intercepteur de flèches.
///
/// Rien d'ici ne se monte avec `legacy` : l'app garde alors la politique de
/// parcours, l'action des flèches et le garde-fou d'avant la refonte.
abstract final class TvNavRoot {
  /// [TvBack] autour de `MaterialApp`.
  static Widget aboveApp({
    required GlobalKey<NavigatorState> navigatorKey,
    required Widget child,
  }) =>
      TvBack(navigatorKey: navigatorKey, child: child);

  /// Les raccourcis de `MaterialApp` : ceux de Flutter, plus OK et Retour de
  /// la télécommande. Pas les raccourcis directionnels du navigateur d'un
  /// téléviseur LG : sous dpad, ses flèches et Entrée passent par le jeu de
  /// touches d'`OnyxDpad`.
  static Map<ShortcutActivator, Intent> get shortcuts =>
      <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        ...tvRemoteShortcuts(webTv: false),
      };

  /// Les actions de `MaterialApp` : celles de Flutter, sans l'ancienne action
  /// des flèches (`TvDirectionalFocusAction`).
  ///
  /// [TvBackAction] reste : quand [TvBack] rend une touche Retour (rien à
  /// dépiler sur le navigateur racine), elle continue vers la coquille, dont
  /// le `PopScope` remonte à l'en-tête puis demande avant de quitter, comme
  /// avant la refonte. La règle de la racine change en phase 5.
  static Map<Type, Action<Intent>> get actions => <Type, Action<Intent>>{
        ...WidgetsApp.defaultActions,
        TvBackIntent: TvBackAction(),
      };

  /// [OnyxDpad] et [TvArrowGate] autour du navigateur.
  static Widget belowApp({
    required String? profileKey,
    required Widget child,
  }) =>
      OnyxDpad(
        profileKey: profileKey,
        child: TvArrowGate(child: child),
      );
}
