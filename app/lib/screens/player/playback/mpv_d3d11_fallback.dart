import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/client_log.dart';
import '../../../utils/app_platform.dart';
import '../hardware_decoding.dart';
import '../player_engine.dart';
import '../windows_video_render.dart';

/// Ce que les compteurs de la sortie disent de la texture D3D11.
enum D3D11Health {
  /// Elle rend, ou il n'y a rien à juger (pause, autre chemin, pas de réponse).
  ok,

  /// Aucun rendu réussi depuis la première image annoncée : écran noir.
  blank,

  /// Le périphérique a disparu (TDR, pilote redémarré).
  deviceLost,

  /// Les rendus échouent et plus aucun ne réussit.
  failing,
}

/// Surveille la texture D3D11 pendant toute la lecture et, en Automatique,
/// fait passer la lecture en cours sur ANGLE dès qu'elle ne montre plus rien
/// (ADR-0158, phase 2, point 4).
///
/// La bascule garde le même lecteur mpv, donc le moteur mis en commun, la
/// position, le son et les pistes : seule la sortie vidéo change, et la piste
/// vidéo est resélectionnée derrière.
class MpvD3D11Fallback {
  MpvD3D11Fallback({
    required this.engine,
    required this.read,
    required this.set,
    required this.suspended,
    required this.onPath,
  });

  final PlayerEngine engine;
  final Future<String?> Function(String name) read;
  final Future<void> Function(String name, String value) set;

  /// Vrai quand la texture n'est plus la sortie (fenêtre d'un profil 5,
  /// ADR-0061) : elle n'a alors plus rien à rendre.
  final bool Function() suspended;

  /// Le nouveau chemin, une fois la bascule faite.
  final void Function(VideoRenderPath? path) onPath;

  /// Le délai laissé à la texture, après la première image annoncée, pour
  /// avoir rendu quelque chose. mpv rend avant même que l'horloge tourne :
  /// passé ce délai, une texture vide est une panne, pas une attente.
  static const Duration startupGrace = Duration(seconds: 3);

  /// L'écart entre deux relevés. Un appel de méthode non bloquant côté natif.
  static const Duration interval = Duration(seconds: 2);

  /// Des rendus ratés en plus entre deux relevés, sans aucun réussi, à partir
  /// desquels la texture est tenue pour morte.
  static const int failingThreshold = 10;

  /// Essai sur machine seulement : `--dart-define=ONYX_FORCE_D3D11_FALLBACK=true`
  /// fait passer la première texture D3D11 sur ANGLE comme si elle était
  /// restée noire, sans rien retenir sur disque. Jamais posé par la CI ni par
  /// une version publiée.
  static const bool _forceForTrial =
      bool.fromEnvironment('ONYX_FORCE_D3D11_FALLBACK');

  Timer? _timer;
  DateTime? _since;
  Map<String, Object?>? _previous;
  bool _busy = false;
  bool _done = false;

  /// La règle, à part pour être testée sans GPU.
  static D3D11Health judge({
    required Map<String, Object?>? info,
    Map<String, Object?>? previous,
    required Duration sinceFirstFrame,
  }) {
    if (info == null) return D3D11Health.ok;
    if (VideoRenderPath.parse(info['renderApi'] as String?) !=
        VideoRenderPath.d3d11) {
      return D3D11Health.ok;
    }
    final removed = info['deviceRemovedReason'];
    if (removed is int && removed != 0) return D3D11Health.deviceLost;
    final rendered = info['renderedFrames'];
    final failed = info['failedFrames'];
    if (rendered is! int || failed is! int) return D3D11Health.ok;
    if (rendered == 0 && sinceFirstFrame >= startupGrace) {
      return D3D11Health.blank;
    }
    final before = previous?['renderedFrames'];
    final failedBefore = previous?['failedFrames'];
    if (before is int &&
        failedBefore is int &&
        rendered == before &&
        failed - failedBefore >= failingThreshold) {
      return D3D11Health.failing;
    }
    return D3D11Health.ok;
  }

  /// Commence à surveiller, depuis la première image. Sans effet hors de
  /// Windows, ou après une bascule.
  void watch() {
    if (!AppPlatform.isWindows || _done) return;
    stop();
    _since = DateTime.now();
    _previous = null;
    _timer = Timer(startupGrace, () {
      unawaited(_check());
      _timer = Timer.periodic(interval, (_) => unawaited(_check()));
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_busy || _done || suspended()) return;
    _busy = true;
    try {
      Map<String, Object?>? info;
      try {
        info = await engine.renderInfo();
      } catch (e) {
        // Une sortie déjà détruite (lecture fermée entre-temps) ne répond
        // plus : il n'y a rien à juger.
        debugPrint('MpvD3D11Fallback: rendus illisibles: $e');
        return;
      }
      final health = judge(
        info: info,
        previous: _previous,
        sinceFirstFrame: DateTime.now().difference(_since ?? DateTime.now()),
      );
      _previous = info ?? _previous;
      if (health != D3D11Health.ok) {
        await _fail(health, info!);
      } else if (_forceForTrial &&
          VideoRenderPath.parse(info?['renderApi'] as String?) ==
              VideoRenderPath.d3d11) {
        await _fail(D3D11Health.blank, info!, forced: true);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _fail(D3D11Health health, Map<String, Object?> info,
      {bool forced = false}) async {
    _done = true;
    stop();
    final removed = info['deviceRemovedReason'];
    final reason = switch (health) {
      D3D11Health.blank => 'aucune image rendue en '
          '${startupGrace.inSeconds}s (${info['failedFrames']} rendus ratés)',
      D3D11Health.deviceLost => 'périphérique perdu (0x'
          '${(removed as int).toUnsigned(32).toRadixString(16)}), TDR ou '
          'pilote redémarré',
      D3D11Health.failing => 'les rendus échouent '
          '(${info['failedFrames']} ratés, ${info['renderedFrames']} réussis)',
      D3D11Health.ok => '',
    };
    // Écran noir dès le départ : la machine ne sait pas faire, on le retient
    // pour son pilote. Une panne en route peut être passagère.
    await WindowsVideoRender.noteD3D11Failure(
        forced ? 'forcé pour l’essai ($reason)' : reason,
        remember: health == D3D11Health.blank && !forced);
    if (!WindowsVideoRender.fallsBackLive) return;
    try {
      // `vid` avant la bascule : libérer le contexte de rendu désélectionne
      // la piste vidéo de mpv, qu'il faut remettre telle quelle.
      final vid = (await read('vid') ?? '').trim();
      final api = await engine.fallbackToAngle();
      final path = VideoRenderPath.parse(api);
      onPath(path);
      // Le décodeur de l'ancien chemin d'abord : la piste resélectionnée
      // rouvre son décodeur avec lui (la recopie, ADR-0095).
      await set('hwdec', HardwareDecoding.mpvValueFor(path));
      await set('vid', vid.isEmpty || vid == 'no' ? 'auto' : vid);
      ClientLog.error('Rendu vidéo : lecture en cours passée de D3D11 à '
          '${api ?? '?'}');
      // La preuve que la bascule a repris : décodeur et rendus, un peu après.
      await Future<void>.delayed(startupGrace);
      final after = await engine.renderInfo();
      debugPrint('Rendu vidéo : après la bascule, '
          'hwdec=${await read('hwdec-current')} · '
          'rendu=${after?['renderApi']} · '
          '${after?['renderedFrames']} rendus, ${after?['failedFrames']} ratés');
    } catch (e) {
      ClientLog.error('Rendu vidéo : bascule vers ANGLE impossible : $e');
    }
  }
}
