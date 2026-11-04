import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/playback/native_tv_preference.dart';
import 'package:onyx/screens/player/playback/native_tv_presenter.dart';
import 'package:onyx/screens/player/playback/native_tv_screen.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';
import 'package:onyx/screens/player/playback/skip_segments.dart';
import 'package:onyx/screens/player/video_display_mode.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un écran natif qui note ce que le présentateur lui envoie.
class _RecordingScreen implements NativeTvScreen {
  final calls = <String>[];
  final specs = <OnyxAppleNativeSpec>[];
  final fits = <OnyxAppleVideoFit>[];
  final events$ = StreamController<OnyxAppleNativeEvent>.broadcast();
  final prepared = <OnyxAppleLoadSubtitles>[];
  bool failPresent = false;

  @override
  bool softwareRoute = false;

  @override
  bool showsBitmapSubtitle = false;

  @override
  Future<void> prepareSubtitles(OnyxAppleLoadSubtitles subtitles) async =>
      prepared.add(subtitles);

  @override
  Future<void> present(OnyxAppleNativeSpec spec) async {
    calls.add('present');
    specs.add(spec);
    if (failPresent) throw StateError('pas de canal');
  }

  @override
  Future<void> update(OnyxAppleNativeSpec spec) async {
    calls.add('update');
    specs.add(spec);
  }

  @override
  Future<void> dismiss() async => calls.add('dismiss');

  @override
  Future<void> setFit(OnyxAppleVideoFit fit) async => fits.add(fit);

  @override
  Stream<OnyxAppleNativeEvent> get events => events$.stream;
}

NativeTvState _state({
  double rate = 1.0,
  VideoDisplayMode mode = VideoDisplayMode.original,
  NativeTvQuality? quality,
  List<MediaAudioTrack>? serverAudio,
  int selectedAudioIndex = -1,
  List<PlaybackTrack> engineAudio = const [],
  PlaybackTrack? currentEngineAudio,
  SkipSegment? skipSegment,
  bool hasNextEpisode = false,
}) =>
    NativeTvState(
      title: 'Severance',
      subtitle: 'S1:E3 - In Perpetuity',
      posterUrl: 'https://image.tmdb.org/t/p/w500/a.jpg',
      overview: 'Mark découvre…',
      rate: rate,
      rates: const [0.75, 1.0, 1.25, 1.5, 2.0],
      mode: mode,
      quality: quality,
      serverAudio: serverAudio,
      selectedAudioIndex: selectedAudioIndex,
      engineAudio: engineAudio,
      currentEngineAudio: currentEngineAudio,
      skipSegment: skipSegment,
      hasNextEpisode: hasNextEpisode,
    );

OnyxAppleNativeMenu _menu(OnyxAppleNativeSpec spec, String id) =>
    spec.menus.singleWhere((menu) => menu.id == id);

List<String> _checked(OnyxAppleNativeMenu menu) => [
      for (final option in menu.options)
        if (option.selected) option.id,
    ];

OnyxAppleNativeEvent _event(
  OnyxAppleNativeEventKind kind, {
  String? actionId,
  String? menuId,
  String? optionId,
  String? trackId,
  OnyxAppleNativeReason? reason,
}) =>
    OnyxAppleNativeEvent(
      playerId: 1,
      kind: kind,
      actionId: actionId,
      menuId: menuId,
      optionId: optionId,
      trackId: trackId,
      reason: reason,
    );

void main() {
  setUp(AppLanguage.resetForTest);
  tearDown(AppLanguage.resetForTest);

  group('la spec de l’écran natif', () {
    test('porte les métadonnées du média telles quelles', () {
      final spec = NativeTvSpecBuilder.build(_state());

      expect(spec.title, 'Severance');
      expect(spec.subtitle, 'S1:E3 - In Perpetuity');
      expect(spec.posterUrl, 'https://image.tmdb.org/t/p/w500/a.jpg');
      expect(spec.overview, 'Mark découvre…');
    });

    test('coche la vitesse et le format d’image en cours', () {
      final spec = NativeTvSpecBuilder.build(
        _state(rate: 1.25, mode: VideoDisplayMode.fill),
      );

      final speed = _menu(spec, NativeTvIds.speed);
      expect(speed.label, 'Vitesse de lecture');
      expect(speed.options.map((o) => o.label),
          ['0.75×', 'Normale', '1.25×', '1.5×', '2×']);
      expect(_checked(speed), ['1.25']);

      final fit = _menu(spec, NativeTvIds.fit);
      expect(fit.label, 'Format d’image');
      expect(_checked(fit), ['fill']);
    });

    test('la qualité propose Auto, le Direct et l’échelle, comme le menu Onyx',
        () {
      const tiers = [
        QualityTier(
            key: '1080p',
            label: '1080p · 8 Mbit/s',
            height: 1080,
            bitrateBps: 8000000),
        QualityTier(
            key: '720p',
            label: '720p · 4 Mbit/s',
            height: 720,
            bitrateBps: 4000000),
      ];
      final spec = NativeTvSpecBuilder.build(_state(
        quality: const NativeTvQuality(
          tiers: tiers,
          current: '720p',
          isAuto: false,
          autoAvailable: true,
          isLocalPlayback: false,
        ),
      ));

      final quality = _menu(spec, NativeTvIds.quality);
      expect(quality.options.map((o) => o.id),
          ['auto', 'direct', 'tier:1080p', 'tier:720p']);
      expect(quality.options.map((o) => o.label),
          ['Auto', 'Direct', '1080p · 8 Mbit/s', '720p · 4 Mbit/s']);
      expect(_checked(quality), ['tier:720p']);
    });

    test('en Auto, seule la ligne Auto est cochée', () {
      final spec = NativeTvSpecBuilder.build(_state(
        quality: const NativeTvQuality(
          tiers: [],
          current: '720p',
          isAuto: true,
          autoAvailable: true,
          isLocalPlayback: false,
        ),
      ));

      expect(_checked(_menu(spec, NativeTvIds.quality)), ['auto']);
    });

    test('l’audio suit la liste du serveur quand elle existe', () {
      final spec = NativeTvSpecBuilder.build(_state(
        serverAudio: [
          MediaAudioTrack(
              index: 1, typedIndex: 0, codec: 'eac3', language: 'fre'),
          MediaAudioTrack(
              index: 2, typedIndex: 1, codec: 'eac3', language: 'eng'),
        ],
        selectedAudioIndex: 1,
        engineAudio: const [PlaybackTrack(id: '1', language: 'fr')],
      ));

      final audio = _menu(spec, NativeTvIds.audio);
      expect(audio.options.map((o) => o.id), ['index:0', 'index:1']);
      expect(_checked(audio), ['index:1']);
    });

    test('sans liste du serveur, l’audio retombe sur les pistes du moteur', () {
      const french = PlaybackTrack(id: '1', language: 'fr');
      final spec = NativeTvSpecBuilder.build(_state(
        engineAudio: const [french, PlaybackTrack(id: '2', title: 'VO')],
        currentEngineAudio: french,
      ));

      final audio = _menu(spec, NativeTvIds.audio);
      expect(audio.options.map((o) => o.id), ['track:1', 'track:2']);
      expect(audio.options.map((o) => o.label), ['Audio (fr)', 'VO']);
      expect(_checked(audio), ['track:1']);
    });

    test('sans aucune piste, pas de menu Audio', () {
      final spec = NativeTvSpecBuilder.build(_state());

      expect(spec.menus.map((m) => m.id), isNot(contains(NativeTvIds.audio)));
    });

    test('les actions suivent le segment en cours et l’épisode suivant', () {
      expect(NativeTvSpecBuilder.build(_state()).actions, isEmpty);

      final intro = NativeTvSpecBuilder.build(
        _state(skipSegment: SkipSegment.intro),
      );
      expect(intro.actions.single.id, NativeTvIds.skipSegment);
      expect(intro.actions.single.label, 'Passer l’intro');

      final recap = NativeTvSpecBuilder.build(
        _state(skipSegment: SkipSegment.recap, hasNextEpisode: true),
      );
      expect(recap.actions.map((a) => a.label),
          ['Passer le récap', 'Épisode suivant']);
    });

    test('les libellés passent par la l10n', () {
      AppLanguage.notifier.value = AppLanguage.english;
      final spec = NativeTvSpecBuilder.build(
        _state(skipSegment: SkipSegment.intro, hasNextEpisode: true),
      );

      expect(_menu(spec, NativeTvIds.fit).label, 'Aspect ratio');
      expect(spec.actions.map((a) => a.label), ['Skip intro', 'Next episode']);
    });

    test('deux états identiques donnent deux specs égales', () {
      expect(
        NativeTvSpecBuilder.build(_state(skipSegment: SkipSegment.intro)),
        NativeTvSpecBuilder.build(_state(skipSegment: SkipSegment.intro)),
      );
    });
  });

  group('les événements natifs', () {
    test('chaque menu se rend en intention du lecteur', () {
      NativeTvIntent? pick(String menu, String option) => nativeTvIntentOf(
            _event(OnyxAppleNativeEventKind.menuSelected,
                menuId: menu, optionId: option),
          );

      expect((pick(NativeTvIds.speed, '1.5') as NativeTvSetRate).rate, 1.5);
      expect((pick(NativeTvIds.fit, 'fillHeight') as NativeTvSetFit).mode,
          VideoDisplayMode.fillHeight);
      expect((pick(NativeTvIds.quality, 'auto') as NativeTvSetQuality).auto,
          isTrue);
      final direct = pick(NativeTvIds.quality, 'direct') as NativeTvSetQuality;
      expect((direct.auto, direct.key), (false, null));
      expect((pick(NativeTvIds.quality, 'tier:720p') as NativeTvSetQuality).key,
          '720p');
      expect(
        (pick(NativeTvIds.audio, 'index:2') as NativeTvSetAudio).serverIndex,
        2,
      );
      expect(
        (pick(NativeTvIds.audio, 'track:7') as NativeTvSetAudio).engineTrackId,
        '7',
      );
    });

    test('un identifiant inconnu est ignoré plutôt que mal compris', () {
      expect(
        nativeTvIntentOf(_event(OnyxAppleNativeEventKind.menuSelected,
            menuId: 'zoom', optionId: '2')),
        isNull,
      );
      expect(
        nativeTvIntentOf(_event(OnyxAppleNativeEventKind.menuSelected,
            menuId: NativeTvIds.speed, optionId: 'vite')),
        isNull,
      );
      expect(
        nativeTvIntentOf(
            _event(OnyxAppleNativeEventKind.action, actionId: 'autre')),
        isNull,
      );
    });

    test('les actions, la fermeture et le refus', () {
      expect(
        nativeTvIntentOf(_event(OnyxAppleNativeEventKind.action,
            actionId: NativeTvIds.skipSegment)),
        isA<NativeTvSkipSegment>(),
      );
      expect(
        nativeTvIntentOf(_event(OnyxAppleNativeEventKind.action,
            actionId: NativeTvIds.nextEpisode)),
        isA<NativeTvNextEpisode>(),
      );
      final byUser = nativeTvIntentOf(_event(OnyxAppleNativeEventKind.dismissed,
          reason: OnyxAppleNativeReason.userDismissed)) as NativeTvClosed;
      expect(byUser.byUser, isTrue);
      final requested = nativeTvIntentOf(_event(
          OnyxAppleNativeEventKind.dismissed,
          reason: OnyxAppleNativeReason.requested)) as NativeTvClosed;
      expect(requested.byUser, isFalse);
      final refused = nativeTvIntentOf(_event(
          OnyxAppleNativeEventKind.unavailable,
          reason: OnyxAppleNativeReason.softwareRoute)) as NativeTvUnavailable;
      expect(refused.reason, OnyxAppleNativeReason.softwareRoute);
      expect(
        (nativeTvIntentOf(_event(OnyxAppleNativeEventKind.subtitleSelected))
                as NativeTvSetSubtitle)
            .trackId,
        isNull,
      );
    });
  });

  group('le présentateur', () {
    late _RecordingScreen screen;
    late List<NativeTvIntent> intents;
    late NativeTvPresenter presenter;

    setUp(() {
      screen = _RecordingScreen();
      intents = [];
      presenter = NativeTvPresenter(screen: screen, onIntent: intents.add);
    });

    tearDown(() => presenter.dispose());

    test('une spec identique ne repasse pas le pont', () async {
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      presenter.sync(
        wanted: true,
        spec: NativeTvSpecBuilder.build(_state(skipSegment: SkipSegment.intro)),
      );
      presenter.sync(
        wanted: true,
        spec: NativeTvSpecBuilder.build(_state(skipSegment: SkipSegment.intro)),
      );
      await pumpEventQueue();

      expect(screen.calls, ['present', 'update']);
      expect(screen.specs.last.actions.single.id, NativeTvIds.skipSegment);
    });

    test('rien n’est présenté tant que le lecteur n’en veut pas', () async {
      presenter.sync(wanted: false, spec: NativeTvSpecBuilder.build(_state()));
      await pumpEventQueue();

      expect(screen.calls, isEmpty);
      expect(presenter.isShown, isFalse);
    });

    test('rend la main à Flutter le temps qu’il faut, puis revient', () async {
      final spec = NativeTvSpecBuilder.build(_state());
      presenter.sync(wanted: true, spec: spec);
      presenter.sync(wanted: false, spec: spec);
      expect(presenter.isShown, isFalse);
      // Sa propre fermeture n'est pas un retrait.
      screen.events$.add(_event(OnyxAppleNativeEventKind.dismissed,
          reason: OnyxAppleNativeReason.requested));
      await pumpEventQueue();
      presenter.sync(wanted: true, spec: spec);
      await pumpEventQueue();

      expect(screen.calls, ['present', 'dismiss', 'present']);
      expect(intents, isEmpty);
    });

    test('un refus rend l’écran Flutter, pour de bon', () async {
      final spec = NativeTvSpecBuilder.build(_state());
      presenter.sync(wanted: true, spec: spec);
      screen.events$.add(_event(OnyxAppleNativeEventKind.unavailable,
          reason: OnyxAppleNativeReason.softwareRoute));
      await pumpEventQueue();

      expect(presenter.isShown, isFalse);
      expect(intents.single, isA<NativeTvUnavailable>());

      presenter.sync(wanted: true, spec: spec);
      await pumpEventQueue();
      expect(screen.calls, ['present']);
    });

    test('Menu sur la télécommande remonte au lecteur', () async {
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      screen.events$.add(_event(OnyxAppleNativeEventKind.dismissed,
          reason: OnyxAppleNativeReason.userDismissed));
      await pumpEventQueue();

      expect((intents.single as NativeTvClosed).byUser, isTrue);
      expect(presenter.isShown, isFalse);
    });

    test('un choix de menu arrive au lecteur en intention', () async {
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      screen.events$.add(_event(OnyxAppleNativeEventKind.menuSelected,
          menuId: NativeTvIds.speed, optionId: '2.0'));
      await pumpEventQueue();

      expect((intents.single as NativeTvSetRate).rate, 2.0);
      expect(presenter.isShown, isTrue);
    });

    test('une présentation qui échoue côté Dart vaut un refus', () async {
      screen.failPresent = true;
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      await pumpEventQueue();

      expect(presenter.isShown, isFalse);
      expect((intents.single as NativeTvUnavailable).reason,
          OnyxAppleNativeReason.presentationFailed);
    });

    test('le cadrage n’est porté que présenté, et quand il change', () async {
      const screenSize = Size(1920, 1080);
      presenter.syncFit(BoxFit.cover, 2.39, screenSize);
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      presenter.syncFit(BoxFit.cover, 2.39, screenSize);
      presenter.syncFit(BoxFit.cover, 2.39, screenSize);
      presenter.syncFit(BoxFit.contain, 2.39, screenSize);
      await pumpEventQueue();

      expect(screen.fits, [OnyxAppleVideoFit.cover, OnyxAppleVideoFit.contain]);
    });

    test('prépare les pistes texte pour AVKit avant toute ouverture', () async {
      await pumpEventQueue();

      expect(screen.prepared.single.prepareNative, isTrue);
      expect(screen.prepared.single.external, isEmpty);
      expect(screen.calls, isEmpty);
    });

    test('garde la raison d’un refus pour la règle de repli', () async {
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      screen.events$.add(_event(OnyxAppleNativeEventKind.unavailable,
          reason: OnyxAppleNativeReason.presentationFailed));
      await pumpEventQueue();

      expect(presenter.refusal, OnyxAppleNativeReason.presentationFailed);
    });

    test('un sous-titre choisi dans AVKit arrive au lecteur', () async {
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      screen.events$
          .add(_event(OnyxAppleNativeEventKind.subtitleSelected, trackId: '2'));
      screen.events$.add(_event(OnyxAppleNativeEventKind.subtitleSelected));
      await pumpEventQueue();

      expect(
          intents.map((i) => (i as NativeTvSetSubtitle).trackId), ['2', null]);
      expect(presenter.isShown, isTrue);
    });

    test('se ferme en partant', () async {
      presenter.sync(wanted: true, spec: NativeTvSpecBuilder.build(_state()));
      presenter.dispose();
      await pumpEventQueue();

      expect(screen.calls, ['present', 'dismiss']);
    });
  });

  test('le lecteur natif n’est éligible que sur Apple TV', () {
    // La suite tourne sur un ordinateur : jamais tvOS.
    expect(isNativeTvPlayerEligible(), isFalse);
  });

  group('réglage Lecteur Apple TV', () {
    setUp(NativeTvPlayerPreference.resetForTest);

    test('le défaut vaut Onyx', () {
      expect(NativeTvPlayerPreference.defaultMode, NativeTvPlayerMode.onyx);
      expect(NativeTvPlayerPreference.mode, NativeTvPlayerMode.onyx);
    });

    test('le réglage n’est visible que sur tvOS', () {
      expect(NativeTvPlayerPreference.isAvailable(isTvOS: true), isTrue);
      expect(NativeTvPlayerPreference.isAvailable(isTvOS: false), isFalse);
    });

    test('l’éligibilité ne s’active qu’avec tvOS et Natif', () {
      bool eligible(bool tvos, NativeTvPlayerMode mode) =>
          NativeTvPlayerPreference.isEligible(isTvOS: tvos, mode: mode);
      expect(eligible(true, NativeTvPlayerMode.native), isTrue);
      expect(eligible(true, NativeTvPlayerMode.onyx), isFalse);
      expect(eligible(false, NativeTvPlayerMode.native), isFalse);
      expect(eligible(false, NativeTvPlayerMode.onyx), isFalse);
    });

    test('le choix est relu au démarrage, un inconnu retombe sur le défaut',
        () async {
      SharedPreferences.setMockInitialValues(
          {'native_tv_player_mode': 'native'});
      await NativeTvPlayerPreference.initialize();
      expect(NativeTvPlayerPreference.mode, NativeTvPlayerMode.native);

      SharedPreferences.setMockInitialValues({'native_tv_player_mode': '??'});
      await NativeTvPlayerPreference.initialize();
      expect(NativeTvPlayerPreference.mode, NativeTvPlayerMode.onyx);
    });
  });
}
