import 'package:flutter/foundation.dart';

/// Les traces `[DPAD]` de la couche CADENCE (plan de refonte §3), pour la
/// recette sur vraie Apple TV (rapport de phase 0, §5.11).
///
/// Ni le simulateur ni les tests n'ont de surface tactile ni la vraie cadence
/// de la Siri Remote : les réglages de `TvArrowGate`, `TvTouchpad` et
/// `TvRepeatCadence` ne se valident que sur la machine, en lisant ces lignes
/// dans la console de `flutter-tvos run` (ou celle de Xcode). Elles disent la
/// cadence reçue, les flèches retenues, les pas faits, les rafales regroupées
/// et l'élan.
///
/// En mode debug seulement : [kDebugMode] est une constante, et la branche
/// disparaît d'une compilation profile ou release. Le message est construit
/// à la demande, pour ne rien coûter hors debug.
abstract final class TvDpadLog {
  /// Reçoit les lignes à la place de la console, dans les tests.
  @visibleForTesting
  static List<String>? debugSink;

  static void log(String Function() message) {
    final sink = debugSink;
    if (sink != null) {
      sink.add('[DPAD] ${message()}');
      return;
    }
    if (kDebugMode) debugPrint('[DPAD] ${message()}');
  }
}
