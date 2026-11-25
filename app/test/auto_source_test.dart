import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_tracks.dart';
import 'package:onyx/screens/player/playback/auto_source.dart';
import 'package:onyx/services/playback_capabilities.dart';

/// La règle de l'Auto (§4 de `docs/transcodage-adaptatif.md`) : Direct Play,
/// puis recopie, puis transcodage au plus haut, la ligne bornant le débit et
/// le serveur la résolution. Une ligne par cas réel.

/// L'échelle de `server/streaming/quality.go`, débits audio compris, rangée
/// comme le serveur la range (débit décroissant, puis hauteur).
const _ladder = <(String, int, int)>[
  ('2160p-40m', 2160, 40192000),
  ('2160p-20m', 2160, 20192000),
  ('1080p-20m', 1080, 20192000),
  ('2160p', 2160, 12192000),
  ('1080p-10m', 1080, 10160000),
  ('720p-6m', 720, 6160000),
  ('1080p', 1080, 6160000),
  ('1080p-4m', 1080, 4160000),
  ('720p', 720, 3660000),
  ('1080p-2m', 1080, 2128000),
  ('720p-2m', 720, 2128000),
  ('480p', 480, 1928000),
  ('720p-1m', 720, 1096000),
  ('360p', 360, 1128000),
  ('480p-720k', 480, 816000),
  ('360p-420k', 360, 484000),
];

/// L'échelle d'une source de [sourceHeight] lignes ; [fit] donne la tenue
/// par hauteur (absente : un serveur qui ne la dit pas).
List<QualityTier> _tiers(int sourceHeight, {Map<int, String>? fit}) => [
      for (final (key, height, bps) in _ladder)
        if (height <= sourceHeight)
          QualityTier(
            key: key,
            label: key,
            height: height,
            bitrateBps: bps,
            fit: fit == null ? null : fit[height] ?? QualityTier.fitOk,
          ),
    ];

MediaVideoTrack _video(String codec, int height,
        {int bitDepth = 8, String hdr = '', bool dv5 = false}) =>
    MediaVideoTrack(
      codec: codec,
      width: height * 16 ~/ 9,
      height: height,
      bitDepth: bitDepth,
      hdrFormat: hdr,
      needsDolbyVision: dv5,
      pixFmt: bitDepth > 8 ? 'yuv420p10le' : 'yuv420p',
    );

MediaAudioTrack _audio(String codec) => MediaAudioTrack(
      index: 1,
      typedIndex: 0,
      codec: codec,
      channels: 6,
      isDefault: true,
    );

/// Un téléphone ou un boîtier Android TV 4K HDR (ExoPlayer).
const _android4kHdr = PlaybackCapabilities(
  container: 'fmp4',
  videoCodecs: {'h264', 'hevc'},
  audioCodecs: {'aac', 'ac3', 'eac3', 'truehd', 'dts'},
  maxAudioChannels: 8,
  maxVideoBitDepth: 10,
  hdr: true,
  dolbyVision: false,
  label: 'exoplayer 4K HDR',
);

/// Un téléviseur LG : pipeline HEVC Main 10, sans DTS dans le fichier.
final _webOS = PlaybackCapabilities.webOSFrom(
  mseVideo: {'hevc'},
  mseAudio: {'ac3', 'eac3'},
  fileAudio: {'ac3', 'eac3'},
);

const _newServer = AutoSourceServer(transcodeCapacity: true);
const _unmeasured = AutoLine.unmeasured();

const _uhdHevcHdr = (codec: 'hevc', height: 2160, bitDepth: 10, hdr: 'hdr10');

void main() {
  group('chooseAutoSource, une ligne par cas réel', () {
    test('Apple TV HD + 4K HEVC HDR → H.264 SDR en 1080p, jamais plus haut',
        () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
          sourceBps: 40000000,
          tiers: _tiers(2160, fit: const {}),
        ),
        const AutoSourceDevice(
            capabilities: PlaybackCapabilities.aetherWithoutHevc),
        _unmeasured,
        _newServer,
      );
      expect(source.kind, AutoSourceKind.transcode);
      expect(source.blocked, DirectPlayBlock.video);
      expect(source.quality, '1080p');
      expect(source.ceiling, '1080p');
      expect(source.keepHdr, isFalse, reason: 'la puce A8 ne sort pas de HDR');
    });

    test('Apple TV HD + 4K HEVC HDR sur une ligne rapide : toujours 1080p', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
          sourceBps: 40000000,
          tiers: _tiers(2160, fit: const {}),
        ),
        const AutoSourceDevice(
            capabilities: PlaybackCapabilities.aetherWithoutHevc),
        const AutoLine.measured(200000000),
        _newServer,
      );
      expect(source.quality, '1080p-20m',
          reason: 'le plus gros débit de 1080p, jamais un barreau 4K');
    });

    test('Apple TV HD + 1080p H.264 8 bits → Direct Play', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('h264', 1080),
          audio: _audio('eac3'),
          sourceBps: 8000000,
          tiers: _tiers(1080, fit: const {}),
        ),
        const AutoSourceDevice(
            capabilities: PlaybackCapabilities.aetherWithoutHevc),
        _unmeasured,
        _newServer,
      );
      expect(source.isDirectPlay, isTrue);
    });

    test('webOS + MKV DTS → recopie, sans plafond de débit', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
          audio: _audio('dts'),
          sourceBps: 60000000,
          tiers: _tiers(2160, fit: const {}),
        ),
        AutoSourceDevice(capabilities: _webOS),
        _unmeasured,
        _newServer,
      );
      expect(source.kind, AutoSourceKind.copy);
      expect(source.blocked, DirectPlayBlock.audio);
      expect(source.quality, '2160p');
      expect(source.remux, isTrue);
    });

    test('Android 4K HDR sur une ligne à 5 Mbit/s → 1080p, HDR gardé', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video(_uhdHevcHdr.codec, _uhdHevcHdr.height,
              bitDepth: _uhdHevcHdr.bitDepth, hdr: _uhdHevcHdr.hdr),
          audio: _audio('eac3'),
          sourceBps: 40000000,
          tiers: _tiers(2160, fit: const {}),
        ),
        const AutoSourceDevice(capabilities: _android4kHdr),
        const AutoLine.measured(5000000),
        _newServer,
      );
      expect(source.kind, AutoSourceKind.transcode);
      expect(source.blocked, DirectPlayBlock.line);
      // 80 % de 5 Mbit/s : aucun 4K, et 1080p seulement à 2 Mbit/s. La
      // résolution d'abord, puis le débit qui passe à cette résolution.
      expect(source.quality, '1080p-2m');
      expect(source.keepHdr, isTrue);
      expect(source.limitedBy, AutoLimit.none);
    });

    test('serveur 4 cœurs sans GPU, occupé : 1080p trop lourd → 720p', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
          sourceBps: 40000000,
          tiers: _tiers(2160, fit: const {
            2160: QualityTier.fitTooHeavy,
            1080: QualityTier.fitTooHeavy,
          }),
        ),
        const AutoSourceDevice(
            capabilities: PlaybackCapabilities.aetherWithoutHevc),
        _unmeasured,
        _newServer,
      );
      expect(source.quality, '720p');
      expect(source.ceiling, '1080p',
          reason: 'le sommet reste celui de l’appareil : le serveur peut '
              'se libérer');
    });

    test('serveur saturé : le plus bas, en disant que c’est le serveur', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 1080),
          sourceBps: 8000000,
          tiers: _tiers(1080, fit: const {
            1080: QualityTier.fitTooHeavy,
            720: QualityTier.fitTooHeavy,
            480: QualityTier.fitLimit,
            360: QualityTier.fitLimit,
          }),
        ),
        const AutoSourceDevice(
            capabilities: PlaybackCapabilities.aetherWithoutHevc),
        _unmeasured,
        _newServer,
      );
      expect(source.quality, '360p-420k');
      expect(source.limitedBy, AutoLimit.server);
    });

    test('ligne trop lente pour tout : le plus bas, en disant que c’est elle',
        () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 1080),
          sourceBps: 8000000,
          tiers: _tiers(1080, fit: const {}),
        ),
        const AutoSourceDevice(
            capabilities: PlaybackCapabilities.aetherWithoutHevc),
        const AutoLine.measured(400000),
        _newServer,
      );
      expect(source.quality, '360p-420k');
      expect(source.limitedBy, AutoLimit.line);
    });

    test('iGPU libre, ligne à 30 Mbit/s : 4K à 20 Mbit/s, HDR gardé', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
          audio: _audio('eac3'),
          sourceBps: 80000000,
          tiers: _tiers(2160, fit: const {}),
        ),
        const AutoSourceDevice(capabilities: _android4kHdr),
        const AutoLine.measured(30000000),
        _newServer,
      );
      // La ligne ne porte ni le fichier ni sa recopie ; le serveur tient le
      // 4K : c'est la ligne seule qui borne, et seulement le débit.
      expect(source.kind, AutoSourceKind.transcode);
      expect(source.quality, '2160p-20m');
      expect(source.keepHdr, isTrue);
    });

    test('iGPU libre : un Dolby Vision 5 en 4K reste en 4K', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160,
              bitDepth: 10, hdr: 'dolbyvision', dv5: true),
          sourceBps: 30000000,
          tiers: _tiers(2160, fit: const {}),
        ),
        const AutoSourceDevice(capabilities: _android4kHdr),
        _unmeasured,
        _newServer,
      );
      expect(source.blocked, DirectPlayBlock.dolbyVision);
      expect(source.quality, '2160p',
          reason: 'le serveur dit tenir le tone mapping en 4K');
      expect(source.keepHdr, isFalse,
          reason: 'un profil 5 passe par libplacebo et le H.264 (ADR-0060)');
    });

    test('ligne pas encore mesurée : Direct Play d’un 4K lourd (ADR-0065)',
        () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
          audio: _audio('truehd'),
          sourceBps: 80000000,
          tiers: _tiers(2160, fit: const {}),
        ),
        const AutoSourceDevice(capabilities: _android4kHdr),
        _unmeasured,
        _newServer,
      );
      expect(source.isDirectPlay, isTrue);
    });

    group('ancien serveur, sans fit ni transcode_capacity : comme avant', () {
      test('Apple TV HD + 4K HEVC → 1080p, sans auto, remux ni HEVC', () {
        final source = chooseAutoSource(
          AutoSourceFile(
            video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
            tiers: _tiers(2160),
          ),
          const AutoSourceDevice(
              capabilities: PlaybackCapabilities.aetherWithoutHevc),
          _unmeasured,
          AutoSourceServer.legacy,
        );
        expect(source.quality, '1080p');
        expect(source.keepHdr, isFalse);
        expect(source.remux, isFalse);
      });

      test('audio muet → le barreau d’origine, sans remux', () {
        final source = chooseAutoSource(
          AutoSourceFile(
            video: _video('hevc', 2160, bitDepth: 10, hdr: 'hdr10'),
            audio: _audio('dts'),
            sourceBps: 60000000,
            tiers: _tiers(2160),
          ),
          AutoSourceDevice(capabilities: _webOS),
          _unmeasured,
          AutoSourceServer.legacy,
        );
        expect(source.kind, AutoSourceKind.copy);
        expect(source.quality, '2160p');
        expect(source.remux, isFalse);
      });

      test('Dolby Vision 5 → au plus 1080p, comme l’ADR-0060', () {
        final source = chooseAutoSource(
          AutoSourceFile(
            video: _video('hevc', 2160,
                bitDepth: 10, hdr: 'dolbyvision', dv5: true),
            tiers: _tiers(2160),
          ),
          const AutoSourceDevice(capabilities: _android4kHdr),
          _unmeasured,
          AutoSourceServer.legacy,
        );
        expect(source.quality, '1080p');
      });

      test('Direct Play figé → le barreau d’origine, recopié', () {
        final source = chooseAutoSource(
          AutoSourceFile(video: _video('hevc', 2160), tiers: _tiers(2160)),
          const AutoSourceDevice(
              capabilities: _android4kHdr, opensFiles: false),
          _unmeasured,
          AutoSourceServer.legacy,
        );
        expect(source.kind, AutoSourceKind.copy);
        expect(source.quality, '2160p');
      });

      test('sans échelle ni hauteur : le palier 1080p que tous offrent', () {
        final source = chooseAutoSource(
          const AutoSourceFile(),
          const AutoSourceDevice(
              capabilities: PlaybackCapabilities.legacy, opensFiles: false),
          _unmeasured,
          AutoSourceServer.legacy,
        );
        expect(source.quality, '1080p');
      });
    });

    test('suggested_quality borne la résolution avant fit', () {
      final source = chooseAutoSource(
        AutoSourceFile(
          video: _video('hevc', 2160, bitDepth: 10),
          tiers: _tiers(2160, fit: const {}),
        ),
        const AutoSourceDevice(
            capabilities: PlaybackCapabilities.legacy, opensFiles: false),
        _unmeasured,
        const AutoSourceServer(transcodeCapacity: true, heightBound: 720),
      );
      expect(source.quality, '720p');
    });
  });

  // Ce que demandait `webQualityFor` (navigateur), repris ici : la surface
  // borne un transcodage, jamais une recopie.
  group('navigateur', () {
    const browser = PlaybackCapabilities.legacy;
    AutoSource web(String codec, int height, int surface) => chooseAutoSource(
          AutoSourceFile(video: _video(codec, height), tiers: _tiers(height)),
          AutoSourceDevice(
              capabilities: browser, opensFiles: false, screenHeight: surface),
          _unmeasured,
          AutoSourceServer.legacy,
        );

    test('un HEVC 4K se plafonne à la fenêtre', () {
      expect(web('hevc', 2160, 1080).quality, '1080p');
      expect(web('hevc', 2160, 800).quality, '1080p');
      expect(web('hevc', 2160, 700).quality, '720p');
    });

    test('un H.264 recopiable garde sa résolution', () {
      for (final codec in ['h264', 'avc1', 'H264']) {
        final source = web(codec, 2160, 1080);
        expect(source.kind, AutoSourceKind.copy, reason: codec);
        expect(source.quality, '2160p', reason: codec);
      }
    });

    test('jamais plus que la source, et pas de plafond inconnu', () {
      expect(web('hevc', 720, 2160).quality, '720p');
      expect(web('vp9', 1080, 4320).quality, '1080p');
      expect(web('hevc', 2160, 2160).quality, '2160p');
      expect(web('hevc', 2160, 0).quality, '2160p');
    });
  });

  group('nativeTierKey', () {
    test('les seuils sont sous chaque hauteur nominale', () {
      expect(nativeTierKey(2160), '2160p');
      expect(nativeTierKey(1608), '2160p');
      expect(nativeTierKey(1080), '1080p');
      expect(nativeTierKey(804), '1080p');
      expect(nativeTierKey(720), '720p');
      expect(nativeTierKey(576), '720p');
      expect(nativeTierKey(480), '480p');
      expect(nativeTierKey(240), '360p');
      expect(nativeTierKey(0), '1080p');
    });
  });

  test('fitHeightBound : le plus haut barreau ok, 0 sans fit', () {
    expect(fitHeightBound(_tiers(2160)), 0);
    expect(
      fitHeightBound(_tiers(2160, fit: const {2160: QualityTier.fitLimit})),
      1080,
    );
  });
}
