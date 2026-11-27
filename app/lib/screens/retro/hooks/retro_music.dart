import 'dart:async';

import 'package:flutter/foundation.dart';

import 'retro_music_backend.dart';

/// Pilote le fond musical du Rétro (démarrage, boucle et bouton muet).
///
/// Reçoit un [RetroMusicBackend] par plateforme (moteur de lecture natif sur
/// mobile/desktop/TV, `<audio>` sur le web) pour qu'un test puisse vérifier
/// l'état sans charger de lecteur natif.
class RetroMusic extends ChangeNotifier {
  RetroMusic({RetroMusicBackend Function()? backendFactory})
      : _backend = (backendFactory ?? createRetroMusicBackend)();

  final RetroMusicBackend _backend;

  bool _muted = false;
  bool _started = false;
  bool _disposed = false;

  bool get muted => _muted;

  void start() {
    if (_started || _disposed || _muted) return;
    _started = true;
    unawaited(_backend.start());
  }

  void toggleMute() {
    if (_disposed) return;
    _muted = !_muted;
    _backend.setMuted(_muted);
    if (!_muted && !_started) {
      start();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _backend.dispose();
    super.dispose();
  }
}
