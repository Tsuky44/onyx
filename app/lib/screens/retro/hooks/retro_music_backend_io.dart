import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../player/playback/playback_engine.dart';
import '../../player/playback/playback_session.dart';
import 'retro_music_backend.dart';

const String _assetPath = 'assets/audio/retro_theme_cinema.m4a';
const String _cacheFileName = 'onyx_retro_theme_cinema.m4a';
const double _backgroundVolume = 65;

RetroMusicBackend createRetroMusicBackend() => _IoRetroMusicBackend();

/// Lit le fond musical du Rétro sur les plateformes natives via le moteur
/// déjà embarqué (mpv, ExoPlayer ou AetherEngine), sans nouvelle dépendance.
class _IoRetroMusicBackend implements RetroMusicBackend {
  PlaybackSession? _session;
  StreamSubscription<void>? _completionSub;
  double? _previousVolume;
  bool _muted = false;
  bool _disposed = false;

  @override
  Future<void> start() async {
    try {
      final data = await rootBundle.load(_assetPath);
      if (_disposed) return;

      final file = await _materialize(data);
      if (_disposed) return;

      final session = createPlaybackSession();
      if (_disposed) {
        unawaited(session.dispose().catchError((_) {}));
        return;
      }
      _session = session;

      await session.prepare();
      if (_disposed) {
        _releaseSession();
        return;
      }

      _previousVolume = session.volume;
      await session.setVolume(_muted ? 0 : _backgroundVolume);
      if (_disposed) {
        _releaseSession();
        return;
      }

      _completionSub = session.completions.listen((_) {
        if (_disposed || _muted) return;
        unawaited(_replay(session));
      });

      await session.open(
        Uri.file(file.path).toString(),
        play: !_muted,
      );
      if (_disposed) {
        _releaseSession();
      }
    } catch (e) {
      // Un test widget sans plugins natifs ou un appareil sans sortie audio ne
      // doit jamais empêcher la story de s'afficher.
      debugPrint('RetroMusic: lecture impossible: $e');
      _releaseSession();
    }
  }

  Future<File> _materialize(ByteData data) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$_cacheFileName');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }

  Future<void> _replay(PlaybackSession session) async {
    try {
      await session.seek(Duration.zero);
      if (_disposed || _muted) return;
      await session.play();
    } catch (e) {
      debugPrint('RetroMusic: boucle interrompue: $e');
    }
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
    final session = _session;
    if (_disposed || session == null) return;
    unawaited(
      (muted
              ? session.setVolume(0).then((_) => session.pause())
              : session
                  .setVolume(_backgroundVolume)
                  .then((_) => session.play()))
          .catchError((Object e) {
        debugPrint('RetroMusic: bascule son impossible: $e');
      }),
    );
  }

  void _releaseSession() {
    unawaited(_completionSub?.cancel());
    _completionSub = null;
    final session = _session;
    _session = null;
    if (session == null) return;
    final prev = _previousVolume;
    _previousVolume = null;
    unawaited(() async {
      try {
        await session.stop();
        // L'instance mpv mise en commun garde son volume d'une lecture à
        // l'autre : on rend celui d'avant pour ne pas baisser le film suivant.
        if (prev != null) await session.setVolume(prev);
      } catch (_) {
      } finally {
        try {
          await session.dispose();
        } catch (_) {}
      }
    }());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseSession();
  }
}
