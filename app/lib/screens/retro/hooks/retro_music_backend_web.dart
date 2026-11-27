import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'retro_music_backend.dart';

const String _webAssetPath = 'assets/assets/audio/retro_theme_cinema.m4a';
const double _backgroundVolume = 0.65;

RetroMusicBackend createRetroMusicBackend() => _WebRetroMusicBackend();

/// Lit le fond musical du Rétro dans le navigateur (desktop, mobile et webOS)
/// via `<audio>`, en boucle continue.
class _WebRetroMusicBackend implements RetroMusicBackend {
  web.HTMLAudioElement? _audio;
  bool _muted = false;
  bool _disposed = false;

  @override
  Future<void> start() async {
    if (_disposed) return;
    try {
      final url = Uri.base.resolve(_webAssetPath).toString();
      final audio = web.HTMLAudioElement()
        ..src = url
        ..loop = true
        ..preload = 'auto'
        ..volume = _backgroundVolume
        ..muted = _muted;
      _audio = audio;
      if (!_muted) {
        await _safePlay(audio);
      }
    } catch (e) {
      debugPrint('RetroMusic: lecture web impossible: $e');
    }
  }

  Future<void> _safePlay(web.HTMLAudioElement audio) async {
    try {
      await audio.play().toDart;
    } catch (_) {
      // Un navigateur qui bloque l'autoplay silencieux laisse le bouton
      // Rétablir le son activer la musique au premier geste.
    }
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
    final audio = _audio;
    if (_disposed || audio == null) return;
    audio.muted = muted;
    if (!muted && audio.paused) {
      audio.play().toDart.catchError((_) => null);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final audio = _audio;
    _audio = null;
    if (audio == null) return;
    audio.pause();
    audio.src = '';
    audio.load();
    audio.remove();
  }
}
