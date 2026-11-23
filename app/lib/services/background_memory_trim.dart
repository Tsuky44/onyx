import 'dart:async';

import 'package:flutter/widgets.dart';

import '../utils/on_screen.dart';

/// Rend la mémoire des images décodées quand l'app reste longtemps cachée.
///
/// Sur bureau le cache d'images décodées monte à 150 Mo (voir
/// `AppImageCache.configure`) et reste plein tant que l'app tourne : réduite
/// des heures dans la barre des tâches, elle gardait ces affiches que
/// personne ne regarde. Les vider coûte un éclair de vignette au retour (les
/// fichiers restent sur disque, seul le décodage est à refaire), alors on
/// attend [grace] : un aller-retour rapide entre deux fenêtres ne vide rien.
class BackgroundMemoryTrim {
  BackgroundMemoryTrim._();

  static const Duration grace = Duration(seconds: 45);

  static Timer? _timer;
  static bool _attached = false;

  /// Écoute la visibilité de l'app. Sans effet au deuxième appel.
  static void attach({
    Duration after = grace,
    void Function()? onTrim,
  }) {
    if (_attached) return;
    _attached = true;
    void changed() {
      _timer?.cancel();
      _timer = null;
      if (AppForeground.isVisible) return;
      _timer = Timer(after, onTrim ?? trim);
    }

    AppForeground.visible.addListener(changed);
  }

  /// Vide les images décodées. Les images que des widgets montent encore
  /// restent tenues par ceux-ci (`clearLiveImages` n'est pas appelé).
  static void trim() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
  }

  @visibleForTesting
  static void debugReset() {
    _timer?.cancel();
    _timer = null;
    _attached = false;
  }
}
