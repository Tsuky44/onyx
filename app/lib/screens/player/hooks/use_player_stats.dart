import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../playback/playback_session.dart';
import '../widgets/direct_source_label.dart';
import 'use_player_controller.dart';

/// Une mesure de l'onglet « Stats » : son nom et ce qu'elle vaut.
class PlayerStatLine {
  const PlayerStatLine(this.label, this.value);

  final String label;
  final String value;
}

/// Ce que le lecteur fait vraiment, relu sur le moteur tant que l'onglet
/// « Stats » est à l'écran (ADR-0130).
///
/// Dart lit [PlaybackSession.readDiagnostics], que tous les moteurs servent. Une
/// mesure que le moteur ne donne pas s'écrit « — » : une valeur inventée ne se
/// distinguerait pas d'une mesure.
///
/// Rien ne tourne tant que personne ne regarde : l'onglet appelle [watch] en
/// arrivant et [unwatch] en partant.
class PlayerLiveStats extends ChangeNotifier {
  PlayerLiveStats({
    required this.readDiagnostics,
    required this.currentQuality,
    required this.isLocalPlayback,
    required this.videoParams,
    required this.videoTrack,
    this.filePath,
    this.interval = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Celles du lecteur : tout se relit sur son contrôleur, au moment du
  /// relevé (la session change avec la qualité).
  PlayerLiveStats.of(PlayerController controller, {String? filePath})
      : this(
          readDiagnostics: () => controller.session.readDiagnostics(),
          currentQuality: () => controller.currentQuality,
          isLocalPlayback: () => controller.isLocalPlayback,
          videoParams: () => controller.session.videoParams,
          videoTrack: () => controller.mediaTracks?.video,
          filePath: filePath,
        );

  final Future<PlaybackDiagnostics> Function() readDiagnostics;

  /// Le barreau transcodé en cours, ou nul en Direct.
  final String? Function() currentQuality;
  final bool Function() isLocalPlayback;
  final PlaybackVideoParams Function() videoParams;
  final MediaVideoTrack? Function() videoTrack;

  /// Le fichier lu, pour nommer son conteneur.
  final String? filePath;
  final Duration interval;
  final DateTime Function() _now;

  static const String unknown = '—';

  int _watchers = 0;
  Timer? _timer;
  bool _reading = false;
  bool _disposed = false;
  PlaybackDiagnostics _info = PlaybackDiagnostics.none;

  /// Le premier relevé d'octets et son instant : le débit moyen se mesure
  /// depuis l'ouverture de l'onglet, pas depuis le début de la séance.
  int? _bytesAtStart;
  DateTime? _startedAt;

  void watch() {
    if (_disposed) return;
    _watchers++;
    if (_watchers > 1) return;
    unawaited(_read());
    _timer = Timer.periodic(interval, (_) => unawaited(_read()));
  }

  void unwatch() {
    if (_watchers == 0) return;
    _watchers--;
    if (_watchers > 0) return;
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    _bytesAtStart = null;
  }

  Future<void> _read() async {
    if (_reading || _disposed) return;
    _reading = true;
    try {
      _info = await readDiagnostics();
    } catch (_) {
      // Un moteur fermé pendant le relevé (changement de qualité, sortie) :
      // la mesure précédente reste affichée jusqu'au relevé suivant.
      return;
    } finally {
      _reading = false;
    }
    if (_disposed) return;
    final bytes = _info.bytesLoaded;
    // Un compteur reparti de zéro (le moteur s'est rouvert) repart d'ici.
    if (bytes != null && (_bytesAtStart == null || bytes < _bytesAtStart!)) {
      _bytesAtStart = bytes;
      _startedAt = _now();
    }
    notifyListeners();
  }

  /// Les mesures, dans l'ordre du panneau.
  List<PlayerStatLine> get lines {
    final info = _info;
    return [
      PlayerStatLine(tr('Chemin de lecture'), _route),
      PlayerStatLine(tr('Codec vidéo'), _text(info.videoCodec)),
      PlayerStatLine(tr('Décodeur vidéo'), _text(info.hardwareDecoder)),
      PlayerStatLine(tr('Décodeur audio'), _text(info.audioCodec)),
      PlayerStatLine(tr('Images par seconde'), _fps(info.estimatedFps, 2)),
      PlayerStatLine(tr('Cadence du fichier'), _fps(info.containerFps, 3)),
      PlayerStatLine(tr('Images perdues'), _dropped(info)),
      PlayerStatLine(tr('Débit moyen'), _mbps(_averageBitrate(info))),
      PlayerStatLine(tr('Débit vidéo'), _mbps(info.videoBitrate)),
      PlayerStatLine(tr('Format vidéo'), _videoFormat),
      PlayerStatLine(tr('Sortie audio'), _audioDelivery(info)),
      PlayerStatLine(tr('Conteneur'), _container),
    ];
  }

  /// Le fichier lui-même, ou le barreau que le serveur transcode.
  String get _route {
    final quality = currentQuality();
    if (quality == null) {
      return directSourceLabel(local: isLocalPlayback()).label;
    }
    return '${tr('Transcodage')} · ${quality == '2160p' ? '4K' : quality}';
  }

  String get _videoFormat {
    final params = videoParams();
    final track = videoTrack();
    final width = params.width ?? track?.width;
    final height = params.height ?? track?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return unknown;
    }
    // Le HDR du fichier n'arrive à l'écran qu'en Direct : un transcodage le
    // ramène en SDR.
    final hdr = currentQuality() == null ? track?.hdrFormat : null;
    return hdr == null || hdr.isEmpty
        ? '$width × $height'
        : '$width × $height · $hdr';
  }

  String get _container {
    if (currentQuality() != null) return 'HLS';
    final path = filePath;
    if (path == null) return unknown;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot >= path.length - 1 || path.length - dot > 6) {
      return unknown;
    }
    return path.substring(dot + 1).toUpperCase();
  }

  double? _averageBitrate(PlaybackDiagnostics info) {
    final bytes = info.bytesLoaded;
    final start = _bytesAtStart;
    final since = _startedAt;
    if (bytes == null || start == null || since == null) return null;
    final seconds = _now().difference(since).inMilliseconds / 1000;
    // Sous deux secondes, la moyenne n'est qu'un à-coup de remplissage.
    if (seconds < 2) return null;
    return (bytes - start) * 8 / seconds;
  }

  static String _text(String? value) =>
      value == null || value.isEmpty ? unknown : value;

  static String _fps(double? value, int digits) => value == null || value <= 0
      ? unknown
      : '${value.toStringAsFixed(digits)} fps';

  static String _mbps(double? bitsPerSecond) =>
      bitsPerSecond == null || bitsPerSecond <= 0
          ? unknown
          : '${(bitsPerSecond / 1000000).toStringAsFixed(1)} Mb/s';

  static String _dropped(PlaybackDiagnostics info) {
    final display = info.droppedByDisplay;
    final decoder = info.droppedByDecoder;
    if (display == null && decoder == null) return unknown;
    return '${(display ?? 0) + (decoder ?? 0)}';
  }

  /// Ce que le fichier porte et ce qui sort : « 5.1 → stereo » dit un mixage
  /// fait par l'appareil.
  static String _audioDelivery(PlaybackDiagnostics info) {
    final source = info.sourceChannels;
    final output = info.outputChannels;
    if (source == null && output == null) return unknown;
    if (source == null || output == null || source == output) {
      return output ?? source!;
    }
    return '$source → $output';
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
