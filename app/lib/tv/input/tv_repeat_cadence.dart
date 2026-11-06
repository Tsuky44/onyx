import 'package:flutter/foundation.dart';

import '../../utils/app_platform.dart';
import '../siri_remote_touches.dart';
import 'tv_arrow_gate.dart';
import 'tv_dpad_log.dart';

/// Qui règle la cadence d'une flèche maintenue, sous dpad (constat C13).
///
/// dpad ne régule rien. Sur Apple TV, le moteur de flutter-tvos fabrique
/// lui-même la répétition (un minuteur natif, réglé par `TvRemoteConfig`) :
/// on lui donne la cadence au démarrage, et `TvArrowGate` ne retient plus
/// rien. Partout ailleurs (Android TV, le navigateur d'un téléviseur LG), la
/// répétition vient du système et ne se règle pas : `TvArrowGate` la retient.
/// Une seule couche par plateforme : réglée deux fois, la même cadence
/// donnerait le pas de la plus lente des deux, ou un sur deux quand elles
/// tombent mal (110 ms de portail sur 80 ms natifs = un pas toutes les
/// 160 ms, ce qui se passait avec l'ancien système).
///
/// Avec l'ancien système, rien d'ici ne se monte : `main.dart` n'appelle
/// [install] qu'avec `ONYX_TV_NAV=dpad`.
abstract final class TvRepeatCadence {
  /// L'écart entre deux répétitions d'une flèche maintenue : la régulation
  /// de l'ancien système (`TvKeyRepeat`), reprise telle quelle. La phase 0 n'a
  /// perdu aucun pas à 80 ms ; 110 ms laisse de la marge sur une machine
  /// plus lente que le simulateur.
  ///
  /// À valider sur vraie Apple TV : rapport de phase 0, §5.2 (la plus petite
  /// cadence sans pas perdu).
  static const Duration interval = TvArrowGate.defaultRepeatInterval;

  /// Fait croire qu'on tourne (ou non) sur Apple TV, dans les tests.
  @visibleForTesting
  static bool? debugNativeOverride;

  /// Vrai quand la plateforme répète elle-même à la cadence voulue.
  static bool get native => debugNativeOverride ?? AppPlatform.isTvOS;

  /// L'écart que `TvArrowGate` impose entre deux répétitions : nul là où la
  /// plateforme les règle déjà.
  static Duration? get gateRepeatInterval => native ? null : interval;

  /// Donne la cadence au moteur, sur Apple TV seulement. [configure] remplace
  /// l'appel à flutter-tvos dans les tests.
  static void install({
    void Function(Duration interval) configure = configureSiriRemoteRepeat,
  }) {
    if (!native) return;
    configure(interval);
    TvDpadLog.log(() => 'TvRemoteConfig keyRepeatInterval='
        '${interval.inMilliseconds} ms, portail sans régulation');
  }
}
