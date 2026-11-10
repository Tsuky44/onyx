import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/playback/native_tv_decoding.dart';
import 'package:onyx/screens/player/playback/native_tv_source.dart';
import 'package:onyx/services/playback_capabilities.dart';

MediaTracks _tracks(String codec, {int height = 1080}) => MediaTracks.fromJson({
      'video': {'codec_name': codec, 'width': 1920, 'height': height},
      'audio': <Object>[],
      'subtitles': <Object>[],
    });

void main() {
  test('une source sans décodeur matériel ne s’ouvre pas, une session part',
      () async {
    final source = NativeTvSource(eligible: true)
      ..prefetch(() async => _tracks('vc1'), streaming: true);
    expect(await source.defersOpen(), isTrue);
    expect(source.transcodes, isTrue);
    expect(source.obstacle, NativeTvDecodeObstacle.codec);
    expect(source.capabilities, same(PlaybackCapabilities.aetherNativeTv));
  });

  test('une source que la puce décode s’ouvre telle quelle', () async {
    final source = NativeTvSource(eligible: true)
      ..prefetch(() async => _tracks('hevc'), streaming: true);
    expect(await source.defersOpen(), isFalse);
    expect(source.transcodes, isFalse);
    expect(source.capabilities, isNull);
  });

  test('le réglage Onyx ou un fichier téléchargé ne changent rien', () async {
    var asked = 0;
    Future<MediaTracks?> load() async {
      asked++;
      return _tracks('vc1');
    }

    final onyx = NativeTvSource(eligible: false)
      ..prefetch(load, streaming: true);
    final downloaded = NativeTvSource(eligible: true)
      ..prefetch(load, streaming: false);
    expect(await onyx.defersOpen(), isFalse);
    expect(await downloaded.defersOpen(), isFalse);
    expect(asked, 0, reason: 'la liste n’est pas demandée d’avance pour rien');
    expect(onyx.capabilities, isNull);
  });

  test('une liste en échec ou en retard ouvre le fichier tel quel', () async {
    final failing = NativeTvSource(eligible: true)
      ..prefetch(() => Future.error(Exception('hors ligne')), streaming: true);
    expect(await failing.defersOpen(), isFalse);

    // Au-delà du délai de décision (1,5 s de vrai temps).
    final pending = Completer<MediaTracks?>();
    final slow = NativeTvSource(eligible: true)
      ..prefetch(() => pending.future, streaming: true);
    expect(await slow.defersOpen(), isFalse);
    pending.complete(_tracks('vc1'));
  });

  test('la liste n’est demandée qu’une fois, et redemandée après un échec',
      () async {
    var asked = 0;
    final source = NativeTvSource(eligible: true)
      ..prefetch(() async {
        asked++;
        return _tracks('av1');
      }, streaming: true);
    await source.defersOpen();
    final tracks = await source.tracks(() async {
      asked++;
      return null;
    });
    expect(tracks?.video?.codec, 'av1');
    expect(asked, 1);

    final failing = NativeTvSource(eligible: true)
      ..prefetch(() => Future.error(Exception('hors ligne')), streaming: true);
    final retried = await failing.tracks(() async => _tracks('h264'));
    expect(retried?.video?.codec, 'h264');
  });

  test('le barreau est celui de la source, au plus 1080p', () {
    final source = NativeTvSource(eligible: true);
    expect(source.quality(2160), '1080p');
    expect(source.quality(1080), '1080p');
    expect(source.quality(576), '720p');
    expect(source.quality(480), '480p');
  });

  test('une session impossible rend les capacités de l’appareil', () async {
    final source = NativeTvSource(eligible: true)
      ..prefetch(() async => _tracks('mpeg2video'), streaming: true);
    await source.defersOpen();
    source.giveUp();
    expect(source.transcodes, isFalse);
    expect(source.capabilities, isNull);
  });

  test('les capacités de l’écran natif demandent le HEVC et le progressif', () {
    final query = PlaybackCapabilities.aetherNativeTv.toQueryParameters();
    expect(query['encode'], 'hevc');
    expect(query['progressive'], '1');
    expect(query['h264bitdepth'], '8');
    expect(query['vcodec'], 'h264,hevc');
    // Les autres clients envoient la même requête qu’avant.
    final aether = PlaybackCapabilities.aether.toQueryParameters();
    expect(aether.keys,
        isNot(anyElement(isIn(['encode', 'progressive', 'h264bitdepth']))));
  });
}
