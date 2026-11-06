import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../player_menu_choices.dart';
import '../video_display_mode.dart';
import '../widgets/direct_source_label.dart';
import '../widgets/track_label.dart';
import 'native_tv_panels.dart';
import 'native_tv_questions.dart';
import 'playback_session.dart';
import 'skip_segments.dart';
import 'sleep_timer.dart';

/// La spec que reçoit l'écran natif, sous un nom du lecteur.
typedef NativeTvSpec = OnyxAppleNativeSpec;

/// Ce que le lecteur sait à cet instant, de quoi bâtir l'écran natif.
///
/// Des valeurs plutôt que le contrôleur : la construction de la spec se teste
/// sans moteur ni écran. Les temps sont ceux du lecteur (absolus), la spec les
/// passe en temps de l'item avec [timelineOffset].
class NativeTvState {
  const NativeTvState({
    required this.title,
    this.subtitle,
    this.posterUrl,
    this.overview,
    required this.rate,
    required this.rates,
    required this.mode,
    this.quality,
    this.serverAudio,
    this.selectedAudioIndex = -1,
    this.engineAudio = const [],
    this.currentEngineAudio,
    this.skipSegment,
    this.hasNextEpisode = false,
    this.sleep,
    this.chapters = const [],
    this.duration = Duration.zero,
    this.timelineOffset = Duration.zero,
    this.canGoPrevious = false,
    this.canGoNext = false,
    this.nextUp,
    this.question,
    this.episodes,
    this.watchParty,
    this.toast,
    this.interceptSeeks = false,
  });

  final String title;
  final String? subtitle;
  final String? posterUrl;
  final String? overview;
  final double rate;
  final List<double> rates;
  final VideoDisplayMode mode;

  /// Null quand la qualité n'a pas de menu (lecteur pas encore initialisé).
  final NativeTvQuality? quality;

  /// La liste canonique du serveur, ou null : on retombe alors sur les pistes
  /// que le moteur a énumérées, comme le menu Onyx.
  final List<MediaAudioTrack>? serverAudio;
  final int selectedAudioIndex;
  final List<PlaybackTrack> engineAudio;
  final PlaybackTrack? currentEngineAudio;

  /// Le segment que « Passer » propose maintenant, ou null.
  final SkipSegment? skipSegment;

  /// L'action contextuelle « Épisode suivant » : au générique seulement.
  final bool hasNextEpisode;

  /// La minuterie de veille, ou null pour ne pas proposer son menu.
  final NativeTvSleep? sleep;

  final List<VideoChapter> chapters;

  /// La durée du média, qui ferme le dernier chapitre.
  final Duration duration;

  /// Où commence l'item que joue AVKit sur la timeline du média : le début
  /// d'une session HLS, zéro en Direct Play.
  final Duration timelineOffset;

  /// Les boutons du panneau d'infos (`infoViewActions`).
  final bool canGoPrevious;
  final bool canGoNext;

  final NativeTvNextUpState? nextUp;
  final NativeTvQuestion? question;

  /// Null hors d'un épisode : pas d'onglet Épisodes.
  final NativeTvEpisodes? episodes;

  /// Null là où aucune séance ne peut s'ouvrir (visiteur d'un lien de partage).
  final NativeTvWatchParty? watchParty;
  final String? toast;
  final bool interceptSeeks;
}

/// L'état du menu Qualité.
class NativeTvQuality {
  const NativeTvQuality({
    required this.tiers,
    required this.current,
    required this.isAuto,
    required this.autoAvailable,
    required this.isLocalPlayback,
    this.directHasWrongColours = false,
  });

  final List<QualityTier> tiers;

  /// La clé du barreau joué, ou null en Direct Play.
  final String? current;
  final bool isAuto;
  final bool autoAvailable;
  final bool isLocalPlayback;

  /// Un Dolby Vision profil 5 que ce moteur montrerait rose et vert
  /// (ADR-0060) : le Direct reste proposé, en le disant.
  final bool directHasWrongColours;
}

/// L'état du menu Minuterie de veille, relevé sur [SleepTimer].
class NativeTvSleep {
  const NativeTvSleep({
    required this.offersEpisodes,
    this.chosen,
    this.remaining,
    this.episodesChosen,
    this.episodesLeft,
  });

  /// [offersEpisodes] : devant un épisode seulement, un film n'a pas de
  /// suivant à ne pas lancer.
  factory NativeTvSleep.of(SleepTimer timer, {required bool offersEpisodes}) =>
      NativeTvSleep(
        offersEpisodes: offersEpisodes,
        chosen: timer.chosen,
        remaining: timer.remaining,
        episodesChosen: timer.episodesChosen,
        episodesLeft: timer.episodesLeft,
      );

  final bool offersEpisodes;
  final Duration? chosen;
  final Duration? remaining;
  final int? episodesChosen;
  final int? episodesLeft;

  bool get isActive => chosen != null || episodesLeft != null;
}

/// L'épisode suivant proposé au générique.
class NativeTvNextUpState {
  const NativeTvNextUpState({
    required this.episode,
    required this.transition,
    this.countdownSeconds,
    this.imageUrl,
  });

  final HomeMediaItem episode;

  /// Le moment de la proposition, en temps de l'item : retenu une fois pour
  /// l'épisode, sinon la spec changerait à chaque position.
  final Duration transition;

  /// Null sans compte à rebours : gelé, ou la minuterie s'arrête après cet
  /// épisode.
  final int? countdownSeconds;

  /// En URL absolue, résolue par l'écran.
  final String? imageUrl;
}

/// Les identifiants que Dart donne aux menus et aux actions, rendus tels quels
/// par le natif dans ses événements.
abstract final class NativeTvIds {
  const NativeTvIds._();

  static const speed = 'speed';
  static const fit = 'fit';
  static const quality = 'quality';
  static const audio = 'audio';

  static const sleep = 'sleep';
  static const chapters = 'chapters';
  static const subtitles = 'subtitles';

  static const skipSegment = 'skipSegment';
  static const nextEpisode = 'nextEpisode';
  static const previousEpisode = 'previousEpisode';
  static const cancelAutoPlay = 'cancelAutoPlay';
  static const watchPartyStart = 'watchParty.start';
  static const watchPartyLeave = 'watchParty.leave';

  /// Les questions posées par-dessus le lecteur ([OnyxAppleNativePrompt.id]).
  static const stillWatching = 'stillWatching';
  static const languageGap = 'languageGap';
  static const launchLanguageGap = 'launchLanguageGap';
  static const nextSeason = 'nextSeason';
  static const upcomingEpisode = 'upcomingEpisode';
  static const playingElsewhere = 'playingElsewhere';

  static const questions = {
    stillWatching,
    languageGap,
    launchLanguageGap,
    nextSeason,
    upcomingEpisode,
    playingElsewhere,
  };

  /// Les réponses sont `<question>.<réponse>` : `stillWatching.continue`,
  /// `languageGap.wait`, `nextSeason.request`, `playingElsewhere.resume`…
  static String answer(String prompt, String answer) => '$prompt.$answer';

  static const answerContinue = 'continue';
  static const answerLeave = 'leave';
  static const answerWait = 'wait';
  static const answerDismiss = 'dismiss';
  static const answerRequest = 'request';
  static const answerPlayNext = 'playNext';
  static const answerResume = 'resume';

  /// Les onglets du panneau d'infos ([OnyxAppleNativePanel.id]).
  static const episodesPanel = 'episodes';
  static const watchPartyPanel = 'watchParty';
  static const statsPanel = 'stats';

  /// Les lignes : `episode:<id>`, `member:<id>` ; les onglets `season:<id>`.
  static const episodeRowPrefix = 'episode:';
  static const memberRowPrefix = 'member:';
  static const seasonTabPrefix = 'season:';

  /// Les options du menu `sleep` et `chapters`.
  static const sleepOff = 'off';
  static const sleepEpisodesPrefix = 'episodes:';
  static const sleepMinutesPrefix = 'minutes:';
  static const chapterPrefix = 'chapter:';

  static const qualityAuto = 'auto';
  static const qualityDirect = 'direct';
  static const qualityTierPrefix = 'tier:';

  /// Une piste de la liste du serveur, par son rang.
  static const audioIndexPrefix = 'index:';

  /// Une piste du moteur, par son identifiant.
  static const audioTrackPrefix = 'track:';
}

/// Construit la spec de l'écran natif. Tous les textes sont traduits ici :
/// Swift n'affiche que ce qu'il reçoit. Les textes reprennent ceux de
/// l'interface Onyx (`onyx_settings_menu.dart`, les cartes de fin,
/// `watch_party_overlay.dart`), pour qu'une même chose ne se dise pas de deux
/// façons.
abstract final class NativeTvSpecBuilder {
  const NativeTvSpecBuilder._();

  /// L'épisode suivant n'est proposé qu'après ce délai : une proposition dont
  /// l'heure est déjà passée n'est peut-être pas présentée (à confirmer à
  /// l'appareil).
  static const nextUpLead = Duration(milliseconds: 500);

  static OnyxAppleNativeSpec build(NativeTvState state) {
    return OnyxAppleNativeSpec(
      title: state.title,
      subtitle: state.subtitle,
      posterUrl: state.posterUrl,
      overview: state.overview,
      // Le libellé du bouton de l'interface Onyx (`onyx_controls_layer.dart`).
      settingsLabel: tr('Réglages'),
      menus: [
        _speedMenu(state),
        _fitMenu(state),
        if (state.quality != null) _qualityMenu(state.quality!),
        if (_audioMenu(state) case final audio?) audio,
        if (state.sleep != null) _sleepMenu(state.sleep!),
      ],
      actions: [
        if (state.skipSegment case final segment?)
          OnyxAppleNativeAction(
            id: NativeTvIds.skipSegment,
            label: switch (segment) {
              SkipSegment.recap => tr('Passer le récap'),
              SkipSegment.intro => tr('Passer l’intro'),
            },
          ),
        if (state.hasNextEpisode)
          OnyxAppleNativeAction(
            id: NativeTvIds.nextEpisode,
            label: tr('Épisode suivant'),
          ),
      ],
      chapters: _chapters(state),
      infoActions: [
        if (state.canGoPrevious)
          OnyxAppleNativeAction(
            id: NativeTvIds.previousEpisode,
            label: tr('Épisode précédent'),
          ),
        if (state.canGoNext)
          OnyxAppleNativeAction(
            id: NativeTvIds.nextEpisode,
            label: tr('Épisode suivant'),
          ),
      ],
      nextUp: _nextUp(state),
      prompt: state.question == null
          ? null
          : NativeTvQuestions.prompt(state.question!),
      panels: [
        if (state.episodes != null) NativeTvPanels.episodes(state.episodes!),
        if (state.watchParty != null)
          NativeTvPanels.watchParty(state.watchParty!),
        NativeTvPanels.stats(),
      ],
      toast: state.toast,
      interceptSeeks: state.interceptSeeks,
    );
  }

  static OnyxAppleNativeMenu _speedMenu(NativeTvState state) =>
      OnyxAppleNativeMenu(
        id: NativeTvIds.speed,
        label: tr('Vitesse de lecture'),
        icon: 'speedometer',
        options: [
          for (final rate in state.rates)
            OnyxAppleNativeOption(
              id: '$rate',
              label: PlayerMenuChoices.rateLabel(rate),
              selected: rate == state.rate,
            ),
        ],
      );

  static OnyxAppleNativeMenu _fitMenu(NativeTvState state) =>
      OnyxAppleNativeMenu(
        id: NativeTvIds.fit,
        label: tr('Format d’image'),
        icon: 'aspectratio',
        options: [
          for (final mode in VideoDisplayMode.values)
            OnyxAppleNativeOption(
              id: mode.name,
              label: mode.label,
              detail: mode.description,
              selected: mode == state.mode,
            ),
        ],
      );

  /// Les mêmes lignes que le menu Onyx : Auto quand le serveur annonce ses
  /// débits, le fichier tel quel, puis l'échelle.
  static OnyxAppleNativeMenu _qualityMenu(NativeTvQuality quality) {
    final auto = quality.isAuto;
    final direct = directSourceLabel(
      local: quality.isLocalPlayback,
      streamSubtitle: tr('Le fichier tel quel'),
    );
    return OnyxAppleNativeMenu(
      id: NativeTvIds.quality,
      label: tr('Qualité'),
      icon: 'sparkles.tv',
      options: [
        if (quality.autoAvailable)
          OnyxAppleNativeOption(
            id: NativeTvIds.qualityAuto,
            label: tr('Auto'),
            detail: auto
                ? _playingQualityLabel(quality)
                : tr('S’adapte à la connexion'),
            selected: auto,
          ),
        OnyxAppleNativeOption(
          id: NativeTvIds.qualityDirect,
          label: direct.label,
          detail: quality.directHasWrongColours
              ? tr('Couleurs incorrectes sur cet appareil')
              : _orNull(direct.subtitle),
          selected: !auto && quality.current == null,
        ),
        for (final tier in quality.tiers)
          OnyxAppleNativeOption(
            id: '${NativeTvIds.qualityTierPrefix}${tier.key}',
            label: tier.resolutionLabel,
            detail: tier.bitrateLabel,
            selected: !auto && quality.current == tier.key,
          ),
      ],
    );
  }

  /// Ce qui est joué en ce moment, comme la ligne Auto du menu Onyx.
  static String _playingQualityLabel(NativeTvQuality quality) {
    final current = quality.current;
    if (current == null) {
      return directSourceLabel(local: quality.isLocalPlayback).label;
    }
    for (final tier in quality.tiers) {
      if (tier.key == current) return tier.label;
    }
    return current == '2160p' ? '4K' : current;
  }

  /// Null quand il n'y a aucune piste à proposer.
  static OnyxAppleNativeMenu? _audioMenu(NativeTvState state) {
    final server = state.serverAudio;
    final List<OnyxAppleNativeOption> options;
    if (server != null && server.isNotEmpty) {
      options = [
        for (var i = 0; i < server.length; i++)
          () {
            final (title, detail) = splitTrackLabel(server[i].displayName);
            return OnyxAppleNativeOption(
              id: '${NativeTvIds.audioIndexPrefix}$i',
              label: title,
              detail: detail,
              selected: i == state.selectedAudioIndex,
            );
          }(),
      ];
    } else {
      final engine = state.engineAudio;
      options = [
        for (var i = 0; i < engine.length; i++)
          OnyxAppleNativeOption(
            id: '${NativeTvIds.audioTrackPrefix}${engine[i].id}',
            label: engine[i].id == 'no'
                ? tr('Désactivé')
                : engine[i].title ??
                    (engine[i].language != null
                        ? tr('Audio ({0})', [engine[i].language])
                        : tr('Audio {0}', [i + 1])),
            selected: engine[i] == state.currentEngineAudio,
          ),
      ];
    }
    if (options.isEmpty) return null;
    return OnyxAppleNativeMenu(
      id: NativeTvIds.audio,
      label: tr('Audio'),
      icon: 'speaker.wave.2',
      options: options,
    );
  }

  /// Les lignes du menu Onyx : désactivée, en épisodes devant un épisode,
  /// puis les durées. « reste … » ne s'affiche que sur la ligne choisie.
  static OnyxAppleNativeMenu _sleepMenu(NativeTvSleep sleep) {
    final remaining = sleep.remaining;
    final episodesLeft = sleep.episodesLeft;
    return OnyxAppleNativeMenu(
      id: NativeTvIds.sleep,
      label: tr('Minuterie de veille'),
      icon: 'moon.zzz',
      options: [
        OnyxAppleNativeOption(
          id: NativeTvIds.sleepOff,
          label: tr('Désactivée'),
          selected: !sleep.isActive,
        ),
        if (sleep.offersEpisodes)
          for (final count in SleepTimer.episodeChoices)
            OnyxAppleNativeOption(
              id: '${NativeTvIds.sleepEpisodesPrefix}$count',
              label: count == 1
                  ? tr('À la fin de l’épisode')
                  : tr('Après {0} épisodes', [count]),
              detail: sleep.episodesChosen == count &&
                      episodesLeft != null &&
                      episodesLeft < count
                  ? tr('reste {0}', [_sleepEpisodes(episodesLeft)])
                  : null,
              selected: sleep.episodesChosen == count,
            ),
        for (final choice in SleepTimer.choices)
          OnyxAppleNativeOption(
            id: '${NativeTvIds.sleepMinutesPrefix}${choice.inMinutes}',
            label: _sleepChoiceLabel(choice),
            detail: sleep.chosen == choice && remaining != null
                ? tr('reste {0}', [_sleepRemaining(remaining)])
                : null,
            selected: sleep.chosen == choice,
          ),
      ],
    );
  }

  /// Arrondi à la minute supérieure, comme le menu Onyx : jamais un « 0 min »
  /// qui annoncerait une coupure déjà faite.
  static String _sleepRemaining(Duration remaining) {
    final minutes = (remaining.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    final rest = (minutes % 60).toString().padLeft(2, '0');
    return '${minutes ~/ 60} h $rest';
  }

  static String _sleepEpisodes(int count) =>
      tr('{0} épisode{1}', [count, count > 1 ? 's' : '']);

  static String _sleepChoiceLabel(Duration choice) {
    if (choice.inMinutes < 60) return tr('{0} minutes', [choice.inMinutes]);
    final hours = choice.inHours;
    return hours == 1 ? tr('1 heure') : tr('{0} heures', [hours]);
  }

  /// La fin d'un chapitre est le début du suivant, ou la fin du média pour le
  /// dernier : AVKit veut des plages jointives, les fichiers n'en donnent pas
  /// toujours. Ce qui tombe avant le début de l'item est écarté.
  static List<OnyxAppleNativeChapter> _chapters(NativeTvState state) {
    final chapters = state.chapters;
    final offsetMs = state.timelineOffset.inMilliseconds;
    final result = <OnyxAppleNativeChapter>[];
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final startMs = (chapter.startTime * 1000).round();
      final endMs = i + 1 < chapters.length
          ? (chapters[i + 1].startTime * 1000).round()
          : state.duration > Duration.zero
              ? state.duration.inMilliseconds
              : (chapter.endTime * 1000).round();
      if (endMs - offsetMs <= 0 || endMs <= startMs) continue;
      result.add(OnyxAppleNativeChapter(
        title: chapter.title.isEmpty
            ? tr('Chapitre {0}', [chapter.id])
            : chapter.title,
        startMs: (startMs - offsetMs).clamp(0, endMs - offsetMs),
        endMs: endMs - offsetMs,
      ));
    }
    return result;
  }

  static OnyxAppleNativeNextUp? _nextUp(NativeTvState state) {
    final next = state.nextUp;
    if (next == null) return null;
    final media = next.episode.media;
    final title = next.episode.episodeTitle ?? media.title;
    final code = media.seasonEpisodeCode;
    return OnyxAppleNativeNextUp(
      title: code == null || code.isEmpty ? title : '$code · $title',
      subtitle: _orNull(next.episode.showTitle ?? ''),
      imageUrl: next.imageUrl,
      transitionMs: next.transition.inMilliseconds,
      countdownSeconds: next.countdownSeconds,
      playLabel: tr('Lire'),
      laterLabel: tr('Plus tard'),
    );
  }

  static String? _orNull(String text) => text.isEmpty ? null : text;
}
