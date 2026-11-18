import 'dart:async';
import 'dart:ui' show AppLifecycleState, FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Dit si l'interface tient sa cadence, à partir du temps de chaque image.
///
/// La mémoire ne suffit pas à reconnaître un appareil trop faible : un
/// Raspberry Pi 4 a 4 Go et un processeur graphique d'entrée de gamme, un
/// vieux portable sous Windows a de la mémoire et une puce intégrée datée. Ce
/// qui ne trompe pas, c'est le temps qu'une image met à se construire et à se
/// dessiner. Flutter ne produit d'images que quand quelque chose bouge, donc
/// chaque image mesurée est une animation ou un défilement, exactement ce que
/// le mode léger allège.
///
/// Une image est lente quand sa construction ou son dessin dépasse d'une
/// moitié le budget d'une image (25 ms à 60 Hz). Au budget tout juste, une
/// Apple TV 4K était jugée lente : sur tvOS, le temps de dessin compte aussi
/// l'attente de l'écran, et une milliseconde de trop n'est pas une saccade
/// qu'on voit (ADR-0141). Le verdict tombe sur une fenêtre de [window]
/// images, quand au moins [slowShare] d'entre elles sont lentes : une
/// saccade isolée (une affiche décodée, un shader compilé) n'y suffit pas.
class FrameBudgetWatch {
  FrameBudgetWatch({
    required this.frameBudget,
    this.window = 120,
    this.slowShare = 0.3,
  });

  /// Le budget d'une image à la fréquence de l'écran. Modifiable : l'écran
  /// d'un téléviseur change de fréquence avec le film qu'il montre.
  Duration frameBudget;
  final int window;
  final double slowShare;

  /// Combien une image peut dépasser son budget avant de compter comme lente.
  static const double tolerance = 1.5;

  int _frames = 0;
  int _slow = 0;

  /// Ajoute une image ; vrai quand la fenêtre qu'elle ferme est lente. La
  /// fenêtre repart de zéro dans les deux cas.
  bool add({required Duration build, required Duration raster}) {
    _frames++;
    final limit = frameBudget * tolerance;
    if (build > limit || raster > limit) _slow++;
    if (_frames < window) return false;
    final slow = _slow >= window * slowShare;
    reset();
    return slow;
  }

  /// Oublie la fenêtre en cours : ce qu'elle contenait ne dit plus rien de
  /// l'interface (un film a joué, l'app est passée derrière).
  void reset() {
    _frames = 0;
    _slow = 0;
  }

  /// Le budget d'une image pour une fréquence d'écran. Une fréquence inconnue
  /// ou de cinéma (24 Hz) se juge à 60 Hz : c'est la cadence des pages.
  static Duration budgetFor(double? refreshRate) {
    final rate = refreshRate != null && refreshRate >= 30 ? refreshRate : 60;
    return Duration(microseconds: (1e6 / rate).round());
  }

  /// Le délai avant la première mesure : les premières secondes compilent
  /// leurs shaders et décodent toutes leurs affiches d'un coup, ce qui saccade
  /// sur n'importe quel appareil.
  static const Duration warmUp = Duration(seconds: 5);

  /// Le délai après une pause (un film, l'app en arrière-plan) : le retour
  /// sur la page redécode ses affiches, et l'écran d'un téléviseur repasse de
  /// la fréquence du film à 60 Hz.
  static const Duration settleAfterPause = Duration(seconds: 3);

  /// Le nombre de fenêtres lentes avant le verdict. Une seule pouvait tomber
  /// sur un pic passager ; le verdict propose maintenant un changement à
  /// l'utilisateur, il doit être sûr de lui.
  static const int slowWindowsNeeded = 2;

  /// Surveille les images de [binding] et appelle [onSustainedJank] quand
  /// l'interface ne tient pas sa cadence. Rend de quoi arrêter.
  ///
  /// [paused] dit quand ne pas mesurer : pendant un film, ce que dessine
  /// l'écran est la vidéo et sa fréquence est celle du film (le téléviseur
  /// passe à 24 Hz), rien qui dise si les pages sont fluides. Une Apple TV 4K
  /// était passée en mode léger en lisant un film. L'arrière-plan est exclu
  /// d'office.
  static VoidCallback install(
    SchedulerBinding binding, {
    required VoidCallback onSustainedJank,
    bool Function()? paused,
  }) {
    final watch = FrameBudgetWatch(frameBudget: budgetFor(null));
    final sincePause = Stopwatch();
    var slowWindows = 0;
    var stopped = false;

    bool isPaused() =>
        binding.lifecycleState != AppLifecycleState.resumed ||
        (paused?.call() ?? false);

    void onTimings(List<FrameTiming> timings) {
      if (stopped) return;
      if (isPaused()) {
        watch.reset();
        sincePause
          ..reset()
          ..start();
        return;
      }
      if (sincePause.isRunning && sincePause.elapsed < settleAfterPause) {
        return;
      }
      sincePause.stop();
      watch.frameBudget = budgetFor(
        PlatformDispatcher.instance.displays.firstOrNull?.refreshRate,
      );
      for (final timing in timings) {
        if (!watch.add(
            build: timing.buildDuration, raster: timing.rasterDuration)) {
          continue;
        }
        if (++slowWindows < slowWindowsNeeded) continue;
        onSustainedJank();
        return;
      }
    }

    final start = Timer(warmUp, () {
      if (!stopped) binding.addTimingsCallback(onTimings);
    });
    return () {
      stopped = true;
      start.cancel();
      binding.removeTimingsCallback(onTimings);
    };
  }
}
