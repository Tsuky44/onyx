import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/watch_party.dart';
import 'package:onyx/screens/player/playback/audio_language_gap.dart';
import 'package:onyx/screens/player/playback/native_tv_presenter.dart';
import 'package:onyx/screens/player/playback/sleep_timer.dart';
import 'package:onyx/screens/player/video_display_mode.dart';
import 'package:onyx/screens/player/widgets/track_label.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';

/// La parité de l'écran natif d'Apple TV avec l'interface Onyx, côté Dart :
/// ce que la spec porte en plus des menus de base, et ce que chaque nouvel
/// événement demande au lecteur. Voir `docs/agents/native-tv-parity.md`, §4.2.

NativeTvState _state({
  VideoDisplayMode mode = VideoDisplayMode.original,
  NativeTvQuality? quality,
  List<MediaAudioTrack>? serverAudio,
  int selectedAudioIndex = -1,
  NativeTvSleep? sleep,
  List<VideoChapter> chapters = const [],
  Duration duration = Duration.zero,
  Duration timelineOffset = Duration.zero,
  bool canGoPrevious = false,
  bool canGoNext = false,
  NativeTvNextUpState? nextUp,
  NativeTvQuestion? question,
  NativeTvEpisodes? episodes,
  NativeTvWatchParty? watchParty,
  String? toast,
  bool interceptSeeks = false,
}) =>
    NativeTvState(
      title: 'Severance',
      rate: 1.0,
      rates: const [1.0],
      mode: mode,
      quality: quality,
      serverAudio: serverAudio,
      selectedAudioIndex: selectedAudioIndex,
      sleep: sleep,
      chapters: chapters,
      duration: duration,
      timelineOffset: timelineOffset,
      canGoPrevious: canGoPrevious,
      canGoNext: canGoNext,
      nextUp: nextUp,
      question: question,
      episodes: episodes,
      watchParty: watchParty,
      toast: toast,
      interceptSeeks: interceptSeeks,
    );

OnyxAppleNativeSpec _build(NativeTvState state) =>
    NativeTvSpecBuilder.build(state);

OnyxAppleNativeMenu _menu(OnyxAppleNativeSpec spec, String id) =>
    spec.menus.singleWhere((menu) => menu.id == id);

OnyxAppleNativePanel _panel(OnyxAppleNativeSpec spec, String id) =>
    spec.panels.singleWhere((panel) => panel.id == id);

HomeMediaItem _episode(
  int id, {
  required int number,
  int position = 0,
  bool finished = false,
}) =>
    HomeMediaItem(
      media: Media(
        id: id,
        type: MediaType.episode,
        title: 'Épisode $number',
        duration: 2400,
        seasonNumber: 1,
        episodeNumber: number,
        posterUrl: '/still/$id.jpg',
        createdAt: DateTime(2026),
      ),
      currentPositionSeconds: position,
      duration: 2400,
      isFinished: finished,
      showId: 7,
      showTitle: 'Severance',
      episodeTitle: 'Le titre $number',
    );

OnyxAppleNativeEvent _event(
  OnyxAppleNativeEventKind kind, {
  String? actionId,
  String? menuId,
  String? optionId,
  bool? playing,
  int? positionMs,
  int? fromPositionMs,
  String? panelId,
  String? rowId,
}) =>
    OnyxAppleNativeEvent(
      playerId: 1,
      kind: kind,
      actionId: actionId,
      menuId: menuId,
      optionId: optionId,
      playing: playing,
      positionMs: positionMs,
      fromPositionMs: fromPositionMs,
      panelId: panelId,
      rowId: rowId,
    );

const _season = NextSeason(
  showId: 7,
  showTmdbId: 95396,
  showTitle: 'Severance',
  number: 2,
  name: '',
  requestStatus: '',
  canRequest: true,
);

const _upcoming = UpcomingEpisode(
  showId: 7,
  showTitle: 'Severance',
  seasonNumber: 1,
  number: 9,
  name: '',
  airDate: '2099-01-01',
);

void main() {
  setUp(AppLanguage.resetForTest);
  tearDown(AppLanguage.resetForTest);

  // tvOS ne montre dans la barre de transport que les éléments qui ont une
  // image : sans icône, Qualité, Audio et les autres menus n'apparaissaient
  // pas du tout. Ils passent sous l'engrenage Réglages.
  test('chaque menu passe sous Réglages avec son icône', () {
    final spec = _build(_state(
      quality: const NativeTvQuality(
        tiers: [],
        current: null,
        isAuto: false,
        autoAvailable: false,
        isLocalPlayback: false,
      ),
      serverAudio: [
        MediaAudioTrack(index: 1, typedIndex: 0, codec: 'aac', channels: 2),
      ],
      sleep: const NativeTvSleep(offersEpisodes: false),
    ));

    expect(spec.settingsLabel, 'Réglages');
    expect(spec.menus.map((m) => m.id), [
      NativeTvIds.speed,
      NativeTvIds.fit,
      NativeTvIds.quality,
      NativeTvIds.audio,
      NativeTvIds.sleep,
    ]);
    for (final menu in spec.menus) {
      expect(menu.icon, isNotNull, reason: 'le menu ${menu.id} sans icône');
    }
  });

  group('les secondes lignes des menus', () {
    test('l’audio du serveur se coupe en deux lignes, comme le menu Onyx', () {
      final track = MediaAudioTrack(
          index: 1,
          typedIndex: 0,
          codec: 'eac3',
          language: 'fre',
          title: 'Commentaire du réalisateur et de la monteuse',
          channels: 6);
      final spec = _build(_state(serverAudio: [track], selectedAudioIndex: 0));

      final option = _menu(spec, NativeTvIds.audio).options.single;
      final (title, detail) = splitTrackLabel(track.displayName);
      expect(detail, isNotNull);
      expect((option.label, option.detail), (title, detail));
    });

    test('chaque format d’image dit ce qu’il fait', () {
      final fit = _menu(_build(_state()), NativeTvIds.fit);
      expect(fit.options.map((o) => o.detail),
          VideoDisplayMode.values.map((m) => m.description));
    });

    test('en Auto, la ligne Auto dit ce qui est joué', () {
      const tier = QualityTier(
          key: '1080p',
          label: '1080p · 8 Mbit/s',
          height: 1080,
          bitrateBps: 8000000);
      final spec = _build(_state(
        quality: const NativeTvQuality(
          tiers: [tier],
          current: '1080p',
          isAuto: true,
          autoAvailable: true,
          isLocalPlayback: false,
        ),
      ));

      final auto = _menu(spec, NativeTvIds.quality).options.first;
      expect(auto.detail, '1080p · 8 Mbit/s');
    });

    test('un Direct aux couleurs fausses le dit, comme le menu Onyx', () {
      final spec = _build(_state(
        quality: const NativeTvQuality(
          tiers: [],
          current: null,
          isAuto: false,
          autoAvailable: false,
          isLocalPlayback: false,
          directHasWrongColours: true,
        ),
      ));

      final direct = _menu(spec, NativeTvIds.quality).options.single;
      expect(direct.detail, 'Couleurs incorrectes sur cet appareil');
    });
  });

  group('la minuterie de veille', () {
    test('propose les épisodes devant un épisode seulement', () {
      final episode = _build(_state(
        sleep: const NativeTvSleep(offersEpisodes: true),
      ));
      final movie = _build(_state(
        sleep: const NativeTvSleep(offersEpisodes: false),
      ));

      final episodeIds =
          _menu(episode, NativeTvIds.sleep).options.map((o) => o.id);
      expect(episodeIds.first, NativeTvIds.sleepOff);
      expect(episodeIds, contains('episodes:1'));
      expect(episodeIds, contains('minutes:30'));
      expect(_menu(movie, NativeTvIds.sleep).options.map((o) => o.id),
          isNot(contains('episodes:1')));
    });

    test('désactivée est cochée tant que rien ne court', () {
      final menu = _menu(
          _build(_state(sleep: const NativeTvSleep(offersEpisodes: true))),
          NativeTvIds.sleep);
      expect(menu.options.where((o) => o.selected).map((o) => o.id),
          [NativeTvIds.sleepOff]);
    });

    test('la durée choisie dit ce qu’il reste, arrondi à la minute', () {
      final menu = _menu(
        _build(_state(
          sleep: const NativeTvSleep(
            offersEpisodes: false,
            chosen: Duration(minutes: 30),
            remaining: Duration(minutes: 11, seconds: 5),
          ),
        )),
        NativeTvIds.sleep,
      );

      final chosen = menu.options.singleWhere((o) => o.selected);
      expect(chosen.id, 'minutes:30');
      expect(chosen.label, '30 minutes');
      expect(chosen.detail, 'reste 12 min');
      expect(menu.options.where((o) => o.detail != null), hasLength(1));
    });

    test('le compte en épisodes dit combien il en reste', () {
      final menu = _menu(
        _build(_state(
          sleep: const NativeTvSleep(
            offersEpisodes: true,
            episodesChosen: 3,
            episodesLeft: 2,
          ),
        )),
        NativeTvIds.sleep,
      );

      final chosen = menu.options.singleWhere((o) => o.selected);
      expect(chosen.id, 'episodes:3');
      expect(chosen.detail, 'reste 2 épisodes');
    });

    test('se relève sur SleepTimer', () {
      SleepTimer.instance.resetForTest();
      addTearDown(SleepTimer.instance.resetForTest);
      SleepTimer.instance.startEpisodes(2);

      final sleep = NativeTvSleep.of(SleepTimer.instance, offersEpisodes: true);
      expect(sleep.isActive, isTrue);
      expect(sleep.episodesChosen, 2);
    });
  });

  group('les chapitres', () {
    test('chacun finit où commence le suivant, le dernier à la fin du média',
        () {
      final spec = _build(_state(
        chapters: [
          VideoChapter(id: 1, startTime: 0, endTime: 0, title: 'Ouverture'),
          VideoChapter(id: 2, startTime: 90.5, endTime: 80, title: ''),
        ],
        duration: const Duration(minutes: 45),
      ));

      expect(spec.chapters.map((c) => (c.title, c.startMs, c.endMs)), [
        ('Ouverture', 0, 90500),
        ('Chapitre 2', 90500, 2700000),
      ]);
    });

    test('passent en temps de l’item, ce qui précède le début est écarté', () {
      final spec = _build(_state(
        chapters: [
          VideoChapter(id: 1, startTime: 0, endTime: 60, title: 'A'),
          VideoChapter(id: 2, startTime: 60, endTime: 300, title: 'B'),
          VideoChapter(id: 3, startTime: 300, endTime: 600, title: 'C'),
        ],
        duration: const Duration(seconds: 600),
        timelineOffset: const Duration(seconds: 120),
      ));

      expect(spec.chapters.map((c) => (c.title, c.startMs, c.endMs)), [
        ('B', 0, 180000),
        ('C', 180000, 480000),
      ]);
    });
  });

  group('les boutons du panneau d’infos', () {
    test('aucun par défaut : pas de « Lire depuis le début »', () {
      expect(_build(_state()).infoActions, isEmpty);
    });

    test('épisode précédent puis suivant', () {
      final spec = _build(_state(canGoPrevious: true, canGoNext: true));
      expect(spec.infoActions.map((a) => (a.id, a.label)), [
        (NativeTvIds.previousEpisode, 'Épisode précédent'),
        (NativeTvIds.nextEpisode, 'Épisode suivant'),
      ]);
    });
  });

  group('l’épisode suivant au générique', () {
    test('porte le code, le titre et le compte à rebours de Dart', () {
      final next = _build(_state(
        nextUp: NativeTvNextUpState(
          episode: _episode(4, number: 4),
          transition: const Duration(minutes: 41),
          countdownSeconds: 5,
          imageUrl: 'https://onyx/still/4.jpg',
        ),
      )).nextUp!;

      expect(next.title, 'S01E04 · Le titre 4');
      expect(next.subtitle, 'Severance');
      expect(next.transitionMs, 41 * 60 * 1000);
      expect(next.countdownSeconds, 5);
      expect(next.imageUrl, 'https://onyx/still/4.jpg');
      expect(next.playLabel, 'Lire');
      expect(next.laterLabel, 'Plus tard');
    });

    test('rien à proposer, rien dans la spec', () {
      expect(_build(_state()).nextUp, isNull);
    });

    test('le moment de la proposition est retenu pour l’épisode', () {
      final memory = NativeTvMemory();
      var now = const Duration(minutes: 40);

      expect(memory.nextUpTransition(4, () => now), now);
      now = const Duration(minutes: 41);
      expect(
          memory.nextUpTransition(4, () => now), const Duration(minutes: 40));
      expect(memory.nextUpTransition(5, () => now), now);
    });

    test('« Plus tard » écarte la proposition de cet épisode seulement', () {
      final memory = NativeTvMemory()..deferNextUp(4);
      expect(memory.nextUpDeferred(4), isTrue);
      expect(memory.nextUpDeferred(5), isFalse);
    });
  });

  group('les questions natives', () {
    test('« Vous regardez encore ? » : continuer, ou Menu pour quitter', () {
      final prompt =
          _build(_state(question: const NativeTvStillWatchingQuestion()))
              .prompt!;

      expect(prompt.id, NativeTvIds.stillWatching);
      expect(prompt.title, 'Vous regardez encore ?');
      expect(prompt.actions.map((a) => a.id),
          ['stillWatching.continue', 'stillWatching.leave']);
      expect(prompt.cancelActionId, 'stillWatching.leave');
    });

    test('la lecture passée ailleurs nomme l’appareil', () {
      final prompt = _build(_state(
        question: const NativeTvPlayingElsewhereQuestion('Salon'),
      )).prompt!;

      expect(prompt.message, contains('« Salon »'));
      expect(prompt.actions.map((a) => a.id),
          ['playingElsewhere.resume', 'playingElsewhere.leave']);
    });

    test('la langue manquante, au lancement ou pour le suivant', () {
      const gap = AudioLanguageGap(wanted: 'fre', offered: 'jpn');
      final launch = _build(_state(
        question: const NativeTvLanguageQuestion(gap, atLaunch: true),
      )).prompt!;
      final next = _build(_state(
        question: const NativeTvLanguageQuestion(gap, atLaunch: false),
      )).prompt!;

      expect(launch.id, NativeTvIds.launchLanguageGap);
      expect(next.id, NativeTvIds.languageGap);
      expect(launch.title, startsWith('Cet épisode'));
      expect(next.title, startsWith('L’épisode suivant'));
      expect(next.actions.map((a) => a.id), [
        'languageGap.continue',
        'languageGap.wait',
        'languageGap.dismiss',
      ]);
      expect(next.actions.first.label,
          'Continuer en ${languageNameInSentence('jpn')}');
      expect(next.cancelActionId, 'languageGap.dismiss');
    });

    test('la saison suivante se demande, puis ne se propose plus', () {
      final ask = _build(_state(
        question: const NativeTvNextSeasonQuestion(_season, canPlayNext: true),
      )).prompt!;
      expect(ask.title, 'Saison 2');
      expect(ask.actions.map((a) => (a.id, a.label)), [
        ('nextSeason.request', 'Demander la saison 2'),
        ('nextSeason.playNext', 'Épisode suivant'),
        ('nextSeason.dismiss', 'Non merci'),
      ]);

      const requested = NextSeason(
        showId: 7,
        showTmdbId: 95396,
        showTitle: 'Severance',
        number: 2,
        name: 'Saison 2',
        requestStatus: 'pending',
        canRequest: false,
      );
      final done = _build(_state(
        question:
            const NativeTvNextSeasonQuestion(requested, canPlayNext: false),
      )).prompt!;
      expect(done.actions.map((a) => (a.id, a.label)),
          [('nextSeason.dismiss', 'Fermer')]);
      expect(done.message, startsWith('Cette saison a déjà été demandée'));
    });

    test('l’épisode à venir ne propose la suite que s’il y en a une', () {
      final prompt = _build(_state(
        question: const NativeTvUpcomingQuestion(_upcoming, canPlayNext: false),
      )).prompt!;

      expect(prompt.title, 'Épisode 9');
      expect(prompt.message, startsWith('Cet épisode n’est pas encore sorti'));
      expect(prompt.actions.map((a) => a.id), ['upcomingEpisode.dismiss']);
    });

    test('chaque réponse revient en intention de sa question', () {
      const questions = <NativeTvQuestion>[
        NativeTvStillWatchingQuestion(),
        NativeTvPlayingElsewhereQuestion('Salon'),
        NativeTvLanguageQuestion(
            AudioLanguageGap(wanted: 'fre', offered: 'jpn'),
            atLaunch: true),
        NativeTvNextSeasonQuestion(_season, canPlayNext: true),
        NativeTvUpcomingQuestion(_upcoming, canPlayNext: true),
      ];
      for (final question in questions) {
        final prompt = NativeTvQuestions.prompt(question);
        expect(
            prompt.actions.map((a) => a.id), contains(prompt.cancelActionId));
        for (final action in prompt.actions) {
          final intent = nativeTvIntentOf(_event(
            OnyxAppleNativeEventKind.action,
            actionId: action.id,
          ));
          expect(intent, isA<NativeTvAnswer>(), reason: action.id);
          final answer = intent! as NativeTvAnswer;
          expect(answer.question, prompt.id);
          expect(NativeTvIds.answer(answer.question, answer.answer), action.id);
        }
      }
    });
  });

  group('les panneaux', () {
    test('dans l’ordre : Épisodes, Regarder ensemble, Stats', () {
      final spec = _build(_state(
        episodes: const NativeTvEpisodes(
          seasons: [],
          selectedSeasonId: null,
          episodes: [],
          currentEpisodeId: 1,
          loading: true,
        ),
        watchParty: const NativeTvWatchParty(),
      ));

      expect(spec.panels.map((p) => p.id), [
        NativeTvIds.episodesPanel,
        NativeTvIds.watchPartyPanel,
        NativeTvIds.statsPanel,
      ]);
      expect(
          _build(_state()).panels.map((p) => p.id), [NativeTvIds.statsPanel]);
    });

    test('les épisodes : saisons en onglets, l’épisode joué marqué', () {
      final panel = _panel(
        _build(_state(
          episodes: NativeTvEpisodes(
            seasons: [
              Media(
                  id: 10,
                  type: MediaType.season,
                  title: 'Saison 1',
                  duration: 0,
                  seasonNumber: 1,
                  createdAt: DateTime(2026)),
              Media(
                  id: 11,
                  type: MediaType.season,
                  title: 'Spéciaux',
                  duration: 0,
                  createdAt: DateTime(2026)),
            ],
            selectedSeasonId: 10,
            episodes: [
              _episode(1, number: 1, finished: true),
              _episode(2, number: 2, position: 600),
            ],
            currentEpisodeId: 2,
            loading: false,
            imageUrl: (episode) => 'https://onyx${episode.media.posterUrl}',
          ),
        )),
        NativeTvIds.episodesPanel,
      );

      expect(panel.title, 'Épisodes');
      expect(panel.tabs.map((t) => (t.id, t.label, t.selected)), [
        ('season:10', 'Saison 1', true),
        ('season:11', 'Spéciaux', false),
      ]);
      expect(panel.rows.map((r) => r.id), ['episode:1', 'episode:2']);
      expect(panel.rows.map((r) => r.selected), [false, true]);
      expect(panel.rows.first.progress, isNull);
      expect(panel.rows.last.progress, closeTo(0.25, 0.001));
      expect(panel.rows.last.subtitle, 'Épisode 2');
      expect(panel.rows.last.detail, isNotNull);
      expect(panel.rows.last.imageUrl, 'https://onyx/still/2.jpg');
      expect(panel.rows.every((r) => r.selectable), isTrue);
      expect(panel.message, isNull);
    });

    test('une saison vide le dit, une saison qui charge non', () {
      NativeTvEpisodes empty({required bool loading}) => NativeTvEpisodes(
            seasons: const [],
            selectedSeasonId: 10,
            episodes: const [],
            currentEpisodeId: 1,
            loading: loading,
          );

      expect(
          _panel(_build(_state(episodes: empty(loading: false))),
                  NativeTvIds.episodesPanel)
              .message,
          'Aucun épisode disponible');
      final loading = _panel(_build(_state(episodes: empty(loading: true))),
          NativeTvIds.episodesPanel);
      expect(loading.message, isNull);
      expect(loading.loading, isTrue);
    });

    test('hors séance, Regarder ensemble propose d’en démarrer une', () {
      final idle = _panel(
          _build(_state(watchParty: const NativeTvWatchParty())),
          NativeTvIds.watchPartyPanel);
      expect(idle.title, 'Regarder ensemble');
      expect(idle.actions.map((a) => (a.id, a.label)),
          [(NativeTvIds.watchPartyStart, 'Démarrer une séance')]);
      // Une colonne de présentation, et à côté les trois étapes : un seul
      // paragraphe sur un panneau large comme l'écran faisait « vide ».
      expect(idle.headline, 'Regardez à plusieurs');
      expect(idle.eyebrow, isNull);
      expect(idle.rowsTitle, 'Comment ça marche');
      expect(idle.rows.map((r) => (r.id, r.badge)),
          [('step:1', '1'), ('step:2', '2'), ('step:3', '3')]);
      expect(idle.rows.any((r) => r.selectable), isFalse);
      expect(idle.loading, isFalse);

      final failed = _panel(
        _build(_state(
          watchParty: const NativeTvWatchParty(
            starting: true,
            error: 'Impossible de démarrer la séance. Réessayez.',
          ),
        )),
        NativeTvIds.watchPartyPanel,
      );
      expect(failed.loading, isTrue);
      expect(failed.message, endsWith('Réessayez.'));
    });

    test('en séance : le code, les participants, l’hôte, quitter', () {
      final panel = _panel(
        _build(_state(
          watchParty: const NativeTvWatchParty(
            code: 'K7Q2',
            members: [
              WatchPartyMember(username: 'alex', isHost: true, isYou: true),
              WatchPartyMember(username: '', device: 'iPhone'),
            ],
          ),
        )),
        NativeTvIds.watchPartyPanel,
      );

      // Le code en grand, sous sa petite ligne ; les participants à droite,
      // chacun avec son initiale.
      expect(panel.eyebrow, 'Code de la séance');
      expect(panel.headline, 'K7Q2');
      expect(panel.rowsTitle, '2 participants');
      expect(
          panel.rows
              .map((r) => (r.id, r.title, r.subtitle, r.detail, r.badge)),
          [
            ('member:0', 'alex (vous)', null, 'Hôte', 'A'),
            ('member:1', 'Invité', 'iPhone', null, 'I'),
          ]);
      expect(panel.rows.any((r) => r.selectable), isFalse);
      expect(panel.actions.map((a) => a.id), [NativeTvIds.watchPartyLeave]);
    });

    test('les stats ne portent que les mesures et leurs libellés', () {
      final stats = _panel(_build(_state()), NativeTvIds.statsPanel);

      expect(stats.rows.map((r) => r.id), NativeTvPanels.statsRows);
      expect(
          stats.rows.every((r) => r.detail == null && !r.selectable), isTrue);
      expect(stats.rows.map((r) => r.title), isNot(contains('route')));
    });

    test('les libellés passent par la l10n', () {
      AppLanguage.notifier.value = AppLanguage.english;
      final spec = _build(_state(
        watchParty: const NativeTvWatchParty(code: 'K7Q2'),
        sleep: const NativeTvSleep(offersEpisodes: false),
      ));

      expect(_panel(spec, NativeTvIds.watchPartyPanel).eyebrow,
          'Session code');
      expect(_panel(spec, NativeTvIds.statsPanel).rows.first.title,
          'Playback path');
      expect(_menu(spec, NativeTvIds.sleep).options.last.label, '2 hours');
    });
  });

  test('l’annonce et l’interception des recherches passent telles quelles', () {
    final spec =
        _build(_state(toast: 'alex a mis en pause', interceptSeeks: true));
    expect(spec.toast, 'alex a mis en pause');
    expect(spec.interceptSeeks, isTrue);
    expect(_build(_state()).toast, isNull);
    expect(_build(_state()).interceptSeeks, isFalse);
  });

  test('deux états identiques donnent deux specs égales', () {
    NativeTvState state() => _state(
          sleep: const NativeTvSleep(offersEpisodes: true),
          chapters: [
            VideoChapter(id: 1, startTime: 0, endTime: 60, title: 'A')
          ],
          duration: const Duration(minutes: 1),
          canGoNext: true,
          question: const NativeTvStillWatchingQuestion(),
          watchParty: const NativeTvWatchParty(code: 'K7Q2'),
          toast: 'alex a rejoint',
        );
    expect(_build(state()), _build(state()));
  });

  group('les nouveaux événements natifs', () {
    test('lecture et pause d’AVKit, position comprise', () {
      final intent = nativeTvIntentOf(_event(
        OnyxAppleNativeEventKind.transport,
        playing: false,
        positionMs: 61500,
      ))! as NativeTvTransport;
      expect(intent.playing, isFalse);
      expect(intent.position, const Duration(milliseconds: 61500));

      expect(
          nativeTvIntentOf(
              _event(OnyxAppleNativeEventKind.transport, positionMs: 1000)),
          isNull);
    });

    test('un saut fait par AVKit, ou retenu pour Dart', () {
      final seeked = nativeTvIntentOf(_event(
        OnyxAppleNativeEventKind.userSeeked,
        fromPositionMs: 10000,
        positionMs: 20000,
      ))! as NativeTvUserSeeked;
      expect(seeked.from, const Duration(seconds: 10));
      expect(seeked.position, const Duration(seconds: 20));

      final requested = nativeTvIntentOf(_event(
        OnyxAppleNativeEventKind.seekRequested,
        positionMs: 30000,
      ))! as NativeTvSeekRequested;
      expect(requested.position, const Duration(seconds: 30));

      expect(nativeTvIntentOf(_event(OnyxAppleNativeEventKind.seekRequested)),
          isNull);
    });

    test('la position de l’item passe sur la timeline du média', () {
      expect(
        nativeTvAbsolute(
            const Duration(seconds: 5), const Duration(minutes: 40)),
        const Duration(minutes: 40, seconds: 5),
      );
      expect(nativeTvAbsolute(const Duration(seconds: 5), Duration.zero),
          const Duration(seconds: 5));
    });

    test('la télécommande en main', () {
      expect(nativeTvIntentOf(_event(OnyxAppleNativeEventKind.userActivity)),
          isA<NativeTvUserActivity>());
    });

    test('les actions nouvelles', () {
      NativeTvIntent? action(String id) => nativeTvIntentOf(
          _event(OnyxAppleNativeEventKind.action, actionId: id));

      expect(
          action(NativeTvIds.previousEpisode), isA<NativeTvPreviousEpisode>());
      expect(action(NativeTvIds.cancelAutoPlay), isA<NativeTvCancelAutoPlay>());
      expect(
          action(NativeTvIds.watchPartyStart), isA<NativeTvStartWatchParty>());
      expect(
          action(NativeTvIds.watchPartyLeave), isA<NativeTvLeaveWatchParty>());
      expect(action('unknown.continue'), isNull);
      expect(action('.continue'), isNull);
    });

    test('la minuterie et les chapitres choisis dans un menu', () {
      NativeTvIntent? menu(String id, String option) =>
          nativeTvIntentOf(_event(OnyxAppleNativeEventKind.menuSelected,
              menuId: id, optionId: option));

      final off = menu(NativeTvIds.sleep, 'off')! as NativeTvSetSleep;
      expect((off.episodes, off.duration), (null, null));
      expect(
          (menu(NativeTvIds.sleep, 'episodes:2')! as NativeTvSetSleep).episodes,
          2);
      expect(
          (menu(NativeTvIds.sleep, 'minutes:45')! as NativeTvSetSleep).duration,
          const Duration(minutes: 45));
      expect(menu(NativeTvIds.sleep, 'minutes:0'), isNull);
      expect(menu(NativeTvIds.sleep, 'hours:1'), isNull);
      expect(
          (menu(NativeTvIds.chapters, 'chapter:3')! as NativeTvJumpToChapter)
              .chapterId,
          3);
    });

    test('un épisode ou une saison choisis dans le panneau', () {
      final row = nativeTvIntentOf(_event(
        OnyxAppleNativeEventKind.panelRowSelected,
        panelId: NativeTvIds.episodesPanel,
        rowId: 'episode:42',
      ))! as NativeTvOpenEpisode;
      expect(row.mediaId, 42);

      final tab = nativeTvIntentOf(_event(
        OnyxAppleNativeEventKind.panelTabSelected,
        panelId: NativeTvIds.episodesPanel,
        optionId: 'season:10',
      ))! as NativeTvSelectSeason;
      expect(tab.seasonId, 10);

      // Un participant n'est qu'une ligne d'information.
      expect(
          nativeTvIntentOf(_event(OnyxAppleNativeEventKind.panelRowSelected,
              panelId: NativeTvIds.watchPartyPanel, rowId: 'member:0')),
          isNull);
      expect(
          nativeTvIntentOf(_event(OnyxAppleNativeEventKind.panelRowSelected,
              panelId: NativeTvIds.episodesPanel, rowId: 'episode:x')),
          isNull);
    });
  });
}
