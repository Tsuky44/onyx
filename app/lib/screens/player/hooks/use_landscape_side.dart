import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../utils/app_platform.dart';

/// Déduit de l'accéléromètre de quel côté le téléphone est tenu en paysage.
///
/// Logique pure, sans capteur ni horloge : [PlayerLandscapeLock] lui passe
/// les mesures. Les valeurs suivent la convention d'Android (sensors_plus
/// ramène iOS à la même) : un téléphone tourné vers la gauche, le haut à
/// gauche, lit `x ≈ +9,8`. Le côté rendu suit la même convention, qui n'est
/// pas celle d'iOS : voir [PlayerLandscapeLock.orientationFor].
class LandscapeSideTracker {
  /// Gravité minimale sur l'axe x (m/s²) pour compter comme paysage, soit à
  /// peu près 40° d'inclinaison franche. En dessous, on garde le côté actuel :
  /// une main qui bouge ne retourne pas l'image.
  static const double minSideGravity = 6.5;

  /// Au-delà de cette gravité sur z, le téléphone est presque à plat (posé sur
  /// la table, ou au lit au-dessus du visage) : l'inclinaison latérale ne veut
  /// plus rien dire et l'image ne bouge pas.
  static const double maxFlatGravity = 8.0;

  /// Durée pendant laquelle le côté opposé doit tenir sans interruption avant
  /// de retourner l'image. Le système d'Android réagit en une fraction de
  /// seconde ; ici on attend un vrai retournement, pas un geste.
  static const Duration settleTime = Duration(milliseconds: 700);

  DeviceOrientation? _side;
  DeviceOrientation? _pending;
  Duration? _pendingSince;

  /// Le côté retenu, ou `null` tant qu'aucune mesure franche n'est arrivée.
  DeviceOrientation? get side => _side;

  /// Ajoute une mesure prise à [at]. Rend le nouveau côté quand il change,
  /// sinon `null`.
  DeviceOrientation? add(double x, double y, double z, Duration at) {
    final candidate = _candidate(x, y, z);
    if (candidate == null || candidate == _side) {
      _pending = null;
      return null;
    }
    // Première mesure franche : on suit la main tout de suite, il n'y a pas
    // d'image à retourner.
    if (_side == null) return _side = candidate;
    if (_pending != candidate) {
      _pending = candidate;
      _pendingSince = at;
      return null;
    }
    if (at - _pendingSince! < settleTime) return null;
    _pending = null;
    return _side = candidate;
  }

  /// Oublie le retournement en cours, par exemple quand le lecteur passe en
  /// image dans l'image.
  void cancelPending() => _pending = null;

  static DeviceOrientation? _candidate(double x, double y, double z) {
    if (z.abs() > maxFlatGravity) return null;
    if (x.abs() < minSideGravity || x.abs() < y.abs()) return null;
    return x > 0
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.landscapeRight;
  }
}

/// Garde le lecteur en paysage sur un téléphone et retourne l'image quand on
/// retourne le téléphone, verrou de rotation du système compris.
///
/// Demander les deux paysages laisse le choix au système, qui obéit au verrou
/// de rotation : verrouillé, l'iPhone comme Android restent du côté où le film
/// a démarré, et l'image se retrouve à l'envers dès qu'on retourne le
/// téléphone. Ici on lit l'accéléromètre et on n'autorise qu'un seul côté,
/// celui où se trouve la main, avec le seuil et le délai de
/// [LandscapeSideTracker]. Sans capteur (simulateur, erreur), les deux
/// paysages restent permis et le système décide.
class PlayerLandscapeLock {
  PlayerLandscapeLock({
    required this.isSuspended,
    Stream<AccelerometerEvent>? events,
    bool? mirrored,
  })  : _events = events,
        _mirrored = mirrored ?? AppPlatform.isIOS;

  /// Vrai quand l'image ne doit pas bouger, en image dans l'image par exemple.
  final bool Function() isSuspended;

  final Stream<AccelerometerEvent>? _events;

  /// Le système nomme les deux paysages à l'envers de [LandscapeSideTracker].
  /// Voir [orientationFor]. Vrai sur iPhone ; passé par les tests.
  final bool _mirrored;
  final LandscapeSideTracker _tracker = LandscapeSideTracker();
  final Stopwatch _clock = Stopwatch();
  StreamSubscription<AccelerometerEvent>? _subscription;

  static const _bothSides = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  void start() {
    unawaited(SystemChrome.setPreferredOrientations(_bothSides));
    _clock.start();
    final events = _events ??
        accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval);
    _subscription = events.listen(
      _handle,
      onError: (Object _) {
        // Pas d'accéléromètre : les deux paysages restent permis, le système
        // choisit le côté. Rien d'autre à faire.
      },
      cancelOnError: true,
    );
  }

  void _handle(AccelerometerEvent event) {
    if (isSuspended()) {
      _tracker.cancelPending();
      return;
    }
    final side = _tracker.add(event.x, event.y, event.z, _clock.elapsed);
    if (side == null) return;
    unawaited(SystemChrome.setPreferredOrientations(
      [orientationFor(side, mirrored: _mirrored)],
    ));
  }

  /// Le paysage à demander au système pour le [side] que rend
  /// [LandscapeSideTracker].
  ///
  /// Le suiveur parle comme Android : son `landscapeLeft` est un téléphone
  /// dont le haut est à gauche, et Flutter le porte à Android sous le nom
  /// `landscape`, qui veut dire la même chose. Sur iPhone, Flutter porte ce
  /// même `landscapeLeft` à `UIInterfaceOrientationMaskLandscapeLeft`, qu'iOS
  /// nomme d'après le côté du bouton principal : le *haut* du téléphone est
  /// alors à droite. Demandé tel quel, c'était le paysage opposé à la main,
  /// et l'image passait à l'envers dès la première mesure (iPhone, 1.1.53 et
  /// 1.1.54). Les deux noms s'échangent donc sur iPhone.
  static DeviceOrientation orientationFor(
    DeviceOrientation side, {
    required bool mirrored,
  }) {
    if (!mirrored) return side;
    return switch (side) {
      DeviceOrientation.landscapeLeft => DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeRight => DeviceOrientation.landscapeLeft,
      _ => side,
    };
  }

  /// Arrête le capteur. Ne rend pas l'orientation : c'est l'écran qui sait
  /// s'il passe à l'épisode suivant ou revient au portrait.
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _clock.stop();
  }
}
