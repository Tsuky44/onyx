export 'retro_music_backend_io.dart'
    if (dart.library.js_interop) 'retro_music_backend_web.dart';

/// Interface du lecteur de fond musical du Rétro selon la plateforme.
abstract interface class RetroMusicBackend {
  Future<void> start();
  void setMuted(bool muted);
  void dispose();
}
