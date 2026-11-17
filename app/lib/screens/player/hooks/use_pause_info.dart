import 'dart:async';

import 'package:flutter/foundation.dart';

/// L'écran « Vous regardez » d'un film laissé en pause (ADR-0137) : le
/// compte à rebours qui le fait monter, et ce qui l'en empêche.
///
/// Tant que quelqu'un a mis pause, il monte au bout de cinq secondes sans
/// geste. Chaque geste (souris, touche, menu, barre) le retire s'il est
/// affiché et relance les cinq secondes : il revient dès que la souris
/// s'arrête. Hors pause, il ne guette rien.
class PauseInfoWatch extends ChangeNotifier {
  PauseInfoWatch({
    required this.mayShow,
    this.delay = defaultDelay,
  });

  static const Duration defaultDelay = Duration(seconds: 5);

  /// Relu au bout du compte à rebours : la lecture est toujours en pause, et
  /// rien d'autre ne tient l'écran (menu, volet, question, carte de fin).
  final bool Function() mayShow;

  final Duration delay;

  Timer? _timer;
  bool _paused = false;
  bool _visible = false;
  bool _disposed = false;

  /// L'écran est affiché par-dessus le film.
  bool get visible => _visible;

  /// La pause vient d'être mise par quelqu'un.
  void notePaused() {
    _paused = true;
    // Un écran resté levé d'une pause relancée par un autre chemin (une
    // séance, un autre appareil) ne doit pas réapparaître d'un coup.
    _hide();
    _arm();
  }

  /// Quelqu'un est là : l'écran affiché s'en va, et en pause les cinq
  /// secondes repartent de zéro. Le geste qui a mis pause passe aussi par
  /// ici, juste après [notePaused] : il ne fait que relancer l'attente.
  ///
  /// Renvoie vrai quand l'écran était affiché, pour que l'appelant sache que
  /// ce geste-là a seulement servi à le fermer.
  bool noteActivity() {
    final wasVisible = _hide();
    if (_paused) _arm();
    return wasVisible;
  }

  /// La lecture repart, ou le lecteur s'en va.
  void noteResumed() {
    _paused = false;
    _cancelTimer();
    _hide();
  }

  void _arm() {
    _cancelTimer();
    _timer = Timer(delay, _fire);
  }

  void _fire() {
    _timer = null;
    if (_disposed || _visible || !_paused) return;
    if (!mayShow()) {
      // Un menu ouvert, la barre qu'on fait glisser : l'écran attend qu'ils
      // lâchent la main, puis cinq secondes de calme, sans nouvelle pause.
      _arm();
      return;
    }
    _visible = true;
    notifyListeners();
  }

  bool _hide() {
    if (!_visible) return false;
    _visible = false;
    if (!_disposed) notifyListeners();
    return true;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimer();
    super.dispose();
  }
}
