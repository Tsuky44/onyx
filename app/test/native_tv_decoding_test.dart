import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/playback/native_tv_decoding.dart';

MediaVideoTrack _video(
  String codec, {
  int bitDepth = 8,
  String pixFmt = 'yuv420p',
  String profile = '',
  int doviProfile = 0,
  bool interlaced = false,
}) =>
    MediaVideoTrack(
      codec: codec,
      width: 1920,
      height: 1080,
      bitDepth: bitDepth,
      pixFmt: pixFmt,
      profile: profile,
      doviProfile: doviProfile,
      interlaced: interlaced,
    );

void main() {
  group('avKitDecodeObstacle', () {
    test('AVKit décode en matériel le H.264 8 bits et le HEVC 8 et 10 bits',
        () {
      expect(avKitDecodeObstacle(_video('h264', profile: 'High')), isNull);
      expect(avKitDecodeObstacle(_video('hevc', profile: 'Main')), isNull);
      expect(
        avKitDecodeObstacle(_video('hevc',
            bitDepth: 10, pixFmt: 'yuv420p10le', profile: 'Main 10')),
        isNull,
      );
    });

    test('le Dolby Vision 5, 8.1 et 8.4 est du HEVC décodé en matériel', () {
      for (final profile in [5, 8]) {
        expect(
          avKitDecodeObstacle(_video('hevc',
              bitDepth: 10, pixFmt: 'yuv420p10le', doviProfile: profile)),
          isNull,
          reason: 'profil $profile',
        );
      }
    });

    test('le profil 7 se lit sur sa couche de base, sauf en double couche',
        () {
      final p7 = _video('hevc',
          bitDepth: 10, pixFmt: 'yuv420p10le', doviProfile: 7);
      expect(avKitDecodeObstacle(p7), isNull);
      expect(avKitDecodeObstacle(p7, dualLayerDolbyVision: true),
          NativeTvDecodeObstacle.dualLayerDolbyVision);
    });

    test('les codecs sans décodeur matériel sur Apple TV', () {
      for (final codec in [
        'vc1',
        'wmv3',
        'mpeg2video',
        'mpeg1video',
        'mpeg4',
        'msmpeg4v3',
        'av1',
        'vp9',
      ]) {
        expect(avKitDecodeObstacle(_video(codec)),
            NativeTvDecodeObstacle.codec,
            reason: codec);
      }
    });

    test('le H.264 10 bits, dit par la profondeur, le format ou le profil', () {
      expect(avKitDecodeObstacle(_video('h264', bitDepth: 10)),
          NativeTvDecodeObstacle.bitDepth);
      expect(avKitDecodeObstacle(_video('h264', pixFmt: 'yuv420p10le')),
          NativeTvDecodeObstacle.bitDepth);
      expect(avKitDecodeObstacle(_video('h264', pixFmt: '', profile: 'High 10')),
          NativeTvDecodeObstacle.bitDepth);
      expect(avKitDecodeObstacle(_video('hevc', pixFmt: 'yuv420p12le')),
          NativeTvDecodeObstacle.bitDepth);
    });

    test('la chrominance 4:2:2 ou 4:4:4', () {
      expect(avKitDecodeObstacle(_video('h264', pixFmt: 'yuv422p')),
          NativeTvDecodeObstacle.chroma);
      expect(
          avKitDecodeObstacle(
              _video('hevc', bitDepth: 10, pixFmt: 'yuv444p10le')),
          NativeTvDecodeObstacle.chroma);
      expect(
          avKitDecodeObstacle(
              _video('h264', pixFmt: '', profile: 'High 4:2:2 Intra')),
          NativeTvDecodeObstacle.chroma);
    });

    test('une image entrelacée', () {
      expect(avKitDecodeObstacle(_video('h264', interlaced: true)),
          NativeTvDecodeObstacle.interlaced);
    });

    test('ce que le serveur ne dit pas ne fait pas transcoder', () {
      // Un serveur d'avant : ni format d'image, ni profil, ni entrelacement.
      expect(avKitDecodeObstacle(_video('h264', pixFmt: '')), isNull);
      expect(avKitDecodeObstacle(_video('', pixFmt: '')), isNull);
    });
  });

  test('MediaVideoTrack lit ce que la sonde du serveur publie', () {
    final video = MediaVideoTrack.fromJson({
      'codec_name': 'h264',
      'width': 1920,
      'height': 1080,
      'pix_fmt': 'yuv422p10le',
      'profile': 'High 4:2:2',
      'dovi_profile': 8,
      'interlaced': true,
      'bit_depth': 10,
    });
    expect(video.pixFmt, 'yuv422p10le');
    expect(video.profile, 'High 4:2:2');
    expect(video.doviProfile, 8);
    expect(video.interlaced, isTrue);
  });
}
