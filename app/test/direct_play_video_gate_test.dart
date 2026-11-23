import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_tracks.dart';
import 'package:onyx/screens/player/playback/direct_play_video_gate.dart';
import 'package:onyx/services/playback_capabilities.dart';

/// Une image que la puce ne décode pas en matériel se demande au serveur, et
/// se décide avant d'ouvrir le fichier : sur une Apple TV HD, AetherEngine
/// lirait le HEVC en logiciel et l'image saccaderait.
void main() {
  MediaVideoTrack video(String codec, int height, {int bitDepth = 8}) =>
      MediaVideoTrack(
        codec: codec,
        width: height * 16 ~/ 9,
        height: height,
        bitDepth: bitDepth,
      );

  const appleTvHd = PlaybackCapabilities.aetherWithoutHevc;

  test('un appareil qui lit tout ouvre toujours le fichier', () {
    for (final caps in [
      PlaybackCapabilities.aether,
      PlaybackCapabilities.mpv,
      PlaybackCapabilities.legacy,
    ]) {
      expect(
        serverQualityForUndecodableVideo(
            caps, video('hevc', 2160, bitDepth: 10)),
        isNull,
        reason: caps.label,
      );
    }
  });

  test('sur une Apple TV HD, le H.264 1080p s’ouvre tel quel', () {
    expect(serverQualityForUndecodableVideo(appleTvHd, video('h264', 1080)),
        isNull);
    expect(serverQualityForUndecodableVideo(appleTvHd, video('h264', 720)),
        isNull);
  });

  test('sur une Apple TV HD, le HEVC part au serveur à sa propre hauteur',
      () {
    expect(serverQualityForUndecodableVideo(appleTvHd, video('hevc', 1080)),
        '1080p');
    expect(serverQualityForUndecodableVideo(appleTvHd, video('hevc', 720)),
        '720p');
    expect(
      serverQualityForUndecodableVideo(
          appleTvHd, video('h264', 1080, bitDepth: 10)),
      '1080p',
    );
  });

  test('un 4K ne se demande jamais au-dessus de ce que la puce affiche', () {
    // Demandé en 2160p, le serveur rendrait une image que la puce ne décode
    // pas non plus.
    expect(
      serverQualityForUndecodableVideo(
          appleTvHd, video('hevc', 2160, bitDepth: 10)),
      '1080p',
    );
    expect(serverQualityForUndecodableVideo(appleTvHd, video('h264', 2160)),
        '1080p');
  });

  test('sans image connue, le fichier s’ouvre tel quel', () {
    expect(serverQualityForUndecodableVideo(appleTvHd, null), isNull);
    expect(
        serverQualityForUndecodableVideo(appleTvHd, video('', 0)), isNull);
  });
}
