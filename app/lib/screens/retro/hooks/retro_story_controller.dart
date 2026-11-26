import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Le déroulé de la story du Rétro : quel écran, où en est sa barre, en pause
/// ou non. Sans horloge à lui : l'écran lui passe le temps écoulé à chaque
/// image ([tick]), et un test le fait avancer à la main.
class RetroStoryController extends ChangeNotifier {
  RetroStoryController({
    required this.count,
    this.slideDuration = const Duration(milliseconds: 7500),
  }) : assert(count > 0);

  final int count;

  /// Le temps passé sur un écran avant le suivant.
  final Duration slideDuration;

  int _index = 0;
  double _progress = 0;
  Offset _origin = _forward;

  /// D'où part l'ouverture en cercle d'un écran qui avance seul ou par la
  /// télécommande : le bord droit ; un écran qui recule part du bord gauche.
  static const Offset _forward = Offset(0.9, 0.5);
  static const Offset _backward = Offset(0.1, 0.5);
  bool _paused = false;
  bool _held = false;

  int get index => _index;

  /// Le point d'où le dernier écran s'est ouvert, en part de l'écran (0 à 1) :
  /// là où l'on a touché, sinon un bord.
  Offset get origin => _origin;

  /// La barre de l'écran en cours, de 0 à 1.
  double get progress => _progress;

  /// En pause, par le bouton ou parce qu'on maintient le doigt.
  bool get paused => _paused || _held;

  /// Le dernier écran est arrivé au bout : la story attend qu'on la ferme.
  bool get finished => _index == count - 1 && _progress >= 1;

  bool get isFirst => _index == 0;
  bool get isLast => _index == count - 1;

  void tick(Duration elapsed) {
    if (paused || finished) return;
    _progress += elapsed.inMicroseconds / slideDuration.inMicroseconds;
    if (_progress >= 1) {
      if (isLast) {
        _progress = 1;
      } else {
        _index++;
        _progress = 0;
        _origin = _forward;
      }
    }
    notifyListeners();
  }

  /// Au dernier écran, « suivant » ne boucle pas : il termine sa barre.
  /// [from] est le point touché, en part de l'écran.
  void next({Offset? from}) {
    if (isLast) {
      _progress = 1;
    } else {
      _index++;
      _progress = 0;
      _origin = from ?? _forward;
    }
    notifyListeners();
  }

  /// Au premier écran, « précédent » le reprend du début.
  void previous({Offset? from}) {
    if (_index > 0) {
      _index--;
      _origin = from ?? _backward;
    }
    _progress = 0;
    notifyListeners();
  }

  void goTo(int index) {
    _index = index.clamp(0, count - 1);
    _progress = 0;
    notifyListeners();
  }

  void togglePause() {
    _paused = !_paused;
    notifyListeners();
  }

  /// Le doigt posé : la story s'arrête tant qu'il reste.
  void hold() {
    if (_held) return;
    _held = true;
    notifyListeners();
  }

  void release() {
    if (!_held) return;
    _held = false;
    notifyListeners();
  }
}
