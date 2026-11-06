import 'package:flutter_tvos/flutter_tvos.dart';

import 'touchpad_motion.dart';

/// Branche [onTouch] sur le trackpad de la Siri Remote.
///
/// Le moteur de flutter-tvos ne transmet les points du doigt qu'après la
/// poignée de main `configure`, que `init()` fait (et refait tant que le
/// greffon natif n'est pas prêt). Hors tvOS, `init()` ne fait rien et
/// [onTouch] n'est jamais appelé.
void listenToSiriRemote(
  void Function(TouchpadPhase phase, double x, double y) onTouch,
) {
  final remote = TvRemoteController.instance..init();
  remote.addRawListener((event) {
    final phase = switch (event.phase) {
      TvRemoteTouchPhase.started => TouchpadPhase.began,
      TvRemoteTouchPhase.move => TouchpadPhase.moved,
      TvRemoteTouchPhase.ended ||
      TvRemoteTouchPhase.cancelled =>
        TouchpadPhase.ended,
      TvRemoteTouchPhase.clickStart => TouchpadPhase.clickDown,
      TvRemoteTouchPhase.clickEnd => TouchpadPhase.clickUp,
      // La position du pavé directionnel, pas un doigt qui glisse.
      TvRemoteTouchPhase.loc => null,
    };
    if (phase != null) onTouch(phase, event.x, event.y);
  });
}

/// Règle la cadence de répétition d'une flèche maintenue (et d'un glissé
/// tenu) dans le moteur de flutter-tvos, sans toucher au reste du réglage.
///
/// Envoyé au greffon natif à `init()`, ou tout de suite s'il est déjà fait.
/// Hors tvOS, `TvRemoteConfig` ne fait rien.
void configureSiriRemoteRepeat(Duration interval) {
  final remote = TvRemoteController.instance;
  final current = remote.config;
  remote.config = TvRemoteConfig(
    shortSwipeThreshold: current.shortSwipeThreshold,
    fastSwipeThreshold: current.fastSwipeThreshold,
    dpadDeadZone: current.dpadDeadZone,
    continuousSwipeMoveThreshold: current.continuousSwipeMoveThreshold,
    keyRepeatInitialDelay: current.keyRepeatInitialDelay,
    keyRepeatInterval: interval,
  );
}
