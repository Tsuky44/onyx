import 'package:flutter/foundation.dart';

import 'playback_session.dart';

/// Relève les diagnostics de mpv d'un seul appel hors du thread de
/// l'interface quand [batch] est là, propriété par propriété par [read]
/// sinon.
///
/// `getProperty` de media_kit lit depuis le thread de l'interface et attend
/// que le cœur de mpv soit libre : treize lectures toutes les cinq secondes
/// pendant toute la lecture, chaque seconde avec l'onglet Stats ouvert, y
/// compris pendant un seek ou un remplissage du cache.
final class MpvDiagnosticsReader {
  MpvDiagnosticsReader({required this.read, this.batch});

  final Future<String?> Function(String name) read;
  final Future<Map<String, String?>> Function(List<String> names)? batch;

  bool _batchBroken = false;

  Future<PlaybackDiagnostics> call() async {
    final batch = this.batch;
    if (batch != null && !_batchBroken) {
      try {
        final values = await batch(mpvDiagnosticProperties);
        return readMpvDiagnostics((name) async => values[name]);
      } catch (e) {
        // Un libmpv que l'isolate ne trouve pas : le relevé repasse par le
        // thread de l'interface, comme avant, sans retenter à chaque fois.
        _batchBroken = true;
        debugPrint('mpv: relevé hors interface impossible ($e) — '
            'relevé direct');
      }
    }
    return readMpvDiagnostics(read);
  }
}

/// Les propriétés que lit [readMpvDiagnostics] : à demander d'un seul appel,
/// hors du thread de l'interface, quand le moteur le permet.
const mpvDiagnosticProperties = [
  'video-codec',
  'hwdec-current',
  'container-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'audio-params/channel-count',
  'audio-out-params/channel-count',
  'audio-codec-name',
  'frame-count',
  'estimated-vf-fps',
  'video-bitrate',
  'audio-bitrate',
  'demuxer-cache-state/total-bytes',
];

/// Ce que mpv sait dire de la lecture en cours, lu propriété par propriété.
///
/// [read] rend la valeur d'une propriété mpv, ou null quand il ne l'a pas.
/// Chaque nom lu figure dans [mpvDiagnosticProperties].
Future<PlaybackDiagnostics> readMpvDiagnostics(
    Future<String?> Function(String name) read) async {
  return PlaybackDiagnostics(
    videoCodec: await read('video-codec'),
    // `hwdec-current` est la réponse de mpv, pas ce qu'on lui a demandé : un
    // décodeur qui n'a pas démarré se rabat en silence.
    hardwareDecoder: await read('hwdec-current'),
    containerFps: double.tryParse(await read('container-fps') ?? ''),
    droppedByDisplay: int.tryParse(await read('frame-drop-count') ?? ''),
    droppedByDecoder:
        int.tryParse(await read('decoder-frame-drop-count') ?? ''),
    sourceChannels: await read('audio-params/channel-count'),
    outputChannels: await read('audio-out-params/channel-count'),
    audioCodec: await read('audio-codec-name'),
    renderedFrames: int.tryParse(await read('frame-count') ?? ''),
    // La cadence telle qu'elle sort, pas telle qu'elle est annoncée. mpv la
    // moyenne lui-même sur les dernières images, ce qui évite d'avoir à
    // dériver un compteur sur deux relevés.
    estimatedFps: double.tryParse(await read('estimated-vf-fps') ?? ''),
    videoBitrate: double.tryParse(await read('video-bitrate') ?? ''),
    audioBitrate: double.tryParse(await read('audio-bitrate') ?? ''),
    bytesLoaded:
        int.tryParse(await read('demuxer-cache-state/total-bytes') ?? ''),
  );
}
