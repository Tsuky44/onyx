import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/playback/native_tv_fallback.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';

/// Sur Apple TV, l'écran natif ne montre que ce qu'AVPlayer sait peindre. Un
/// repli manqué, c'est un film sans image (route logicielle : une roue AVKit,
/// son joué) ou sans ses sous-titres (une piste PGS qu'AVKit ignore), sans la
/// moindre erreur. Une piste PGS, elle, reste sur l'écran natif, qui la peint
/// lui-même : la quitter pour Flutter, c'est perdre AVKit pour rien.
void main() {
  group('la règle de repli', () {
    test('rien à redire : l’écran natif', () {
      expect(nativeTvFallbackFor(), isNull);
      expect(nativeTvFallbackFor(subtitle: NativeTvSubtitleKind.text), isNull);
    });

    test('la route logicielle garde Flutter, à l’ouverture comme en cours', () {
      expect(nativeTvFallbackFor(softwareRoute: true),
          NativeTvFallback.softwareRoute);
      // Le natif l'a vue avant Dart : il a refusé pour la même raison.
      expect(nativeTvFallbackFor(refusal: OnyxAppleNativeReason.softwareRoute),
          NativeTvFallback.softwareRoute);
    });

    test('une piste image en Direct Play reste sur l’écran natif', () {
      expect(nativeTvFallbackFor(subtitle: NativeTvSubtitleKind.image), isNull);
    });

    test('une piste image que le natif n’a pas su peindre garde Flutter', () {
      const refusal = OnyxAppleNativeReason.bitmapSubtitles;
      expect(
          nativeTvFallbackFor(
              refusal: refusal, subtitle: NativeTvSubtitleKind.image),
          NativeTvFallback.bitmapSubtitles);
      // Ce refus ne vaut que pour les pistes image : une piste texte, aucune
      // piste ou le HLS (piste incrustée) rendent l'écran natif.
      expect(
          nativeTvFallbackFor(
              refusal: refusal, subtitle: NativeTvSubtitleKind.text),
          isNull);
      expect(nativeTvFallbackFor(refusal: refusal), isNull);
      expect(
          nativeTvFallbackFor(
              refusal: refusal,
              subtitle: NativeTvSubtitleKind.image,
              streaming: true),
          isNull);
    });

    test('en HLS, la piste image est dans l’image, la piste texte non', () {
      // Le transcodeur incruste la piste image : AVPlayer la montre.
      expect(
          nativeTvFallbackFor(
              subtitle: NativeTvSubtitleKind.image, streaming: true),
          isNull);
      // La piste texte, écrite à part, n'est peinte que par Flutter.
      expect(
          nativeTvFallbackFor(
              subtitle: NativeTvSubtitleKind.text, streaming: true),
          NativeTvFallback.overlaySubtitles);
      expect(nativeTvFallbackFor(streaming: true), isNull);
    });

    test('un échec de présentation garde Flutter, quoi que dise le média', () {
      for (final reason in [
        OnyxAppleNativeReason.presentationFailed,
        OnyxAppleNativeReason.unsupported,
      ]) {
        expect(nativeTvFallbackFor(refusal: reason),
            NativeTvFallback.presentationFailed);
        expect(
            nativeTvFallbackFor(
                refusal: reason, subtitle: NativeTvSubtitleKind.image),
            NativeTvFallback.presentationFailed);
      }
    });

    test('priorité : refus, puis route logicielle, puis piste image', () {
      expect(
          nativeTvFallbackFor(
              refusal: OnyxAppleNativeReason.bitmapSubtitles,
              softwareRoute: true,
              subtitle: NativeTvSubtitleKind.image),
          NativeTvFallback.softwareRoute);
      expect(
          nativeTvFallbackFor(
              refusal: OnyxAppleNativeReason.presentationFailed,
              softwareRoute: true),
          NativeTvFallback.presentationFailed);
      expect(
          nativeTvFallbackFor(
              softwareRoute: true,
              streaming: true,
              subtitle: NativeTvSubtitleKind.text),
          NativeTvFallback.softwareRoute);
    });

    test('une fermeture n’est pas un refus', () {
      expect(nativeTvFallbackFor(refusal: OnyxAppleNativeReason.userDismissed),
          isNull);
      expect(nativeTvFallbackFor(refusal: OnyxAppleNativeReason.requested),
          isNull);
    });
  });

  group('le genre du sous-titre retenu', () {
    final server = [
      MediaSubtitleTrack(lang: 'fr', name: 'Français', typedIndex: 0),
      MediaSubtitleTrack(lang: 'img1', name: 'Français (PGS)', image: true),
    ];

    test('aucun choix, aucun sous-titre', () {
      expect(nativeTvSubtitleKind(selectedLang: null, serverTracks: server),
          NativeTvSubtitleKind.none);
      expect(nativeTvSubtitleKind(selectedLang: '', serverTracks: server),
          NativeTvSubtitleKind.none);
    });

    test('une piste choisie ou reprise par la mémoire se lit sur le serveur',
        () {
      expect(nativeTvSubtitleKind(selectedLang: 'fr', serverTracks: server),
          NativeTvSubtitleKind.text);
      expect(nativeTvSubtitleKind(selectedLang: 'img1', serverTracks: server),
          NativeTvSubtitleKind.image);
    });

    test('la piste image active du moteur l’emporte', () {
      // Choisie dans la liste du fichier, sans clé du serveur.
      expect(
          nativeTvSubtitleKind(
              selectedLang: null, serverTracks: null, engineShowsBitmap: true),
          NativeTvSubtitleKind.image);
    });

    test('une clé que le serveur ne liste pas est du texte', () {
      expect(nativeTvSubtitleKind(selectedLang: 'de', serverTracks: null),
          NativeTvSubtitleKind.text);
    });
  });

  group('les sous-titres du menu AVKit', () {
    const tracks = [
      PlaybackTrack(id: '1', language: 'fre'),
      PlaybackTrack(id: '2', language: 'eng'),
    ];

    test('une piste choisie revient telle que le contrôleur la connaît', () {
      expect(nativeTvSubtitleChoice('2', tracks), tracks[1]);
    });

    test('« aucun » devient la piste « no » du contrôleur', () {
      expect(
          nativeTvSubtitleChoice(null, tracks), const PlaybackTrack(id: 'no'));
    });

    test('une piste qui n’est plus listée est ignorée', () {
      expect(nativeTvSubtitleChoice('7', tracks), isNull);
    });

    test('les pistes texte sont préparées pour AVKit au chargement', () {
      final load = nativeTvLoadSubtitles();
      expect(load.prepareNative, isTrue);
      expect(load.external, isEmpty);
    });
  });
}
