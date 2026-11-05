import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../video_display_mode.dart';
import 'native_tv_spec.dart';

/// Ce qu'un événement natif demande au lecteur. Chaque cas a déjà son
/// gestionnaire dans l'écran du lecteur : ce type ne fait que traduire.
sealed class NativeTvIntent {
  const NativeTvIntent();
}

final class NativeTvSkipSegment extends NativeTvIntent {
  const NativeTvSkipSegment();
}

final class NativeTvNextEpisode extends NativeTvIntent {
  const NativeTvNextEpisode();
}

final class NativeTvPreviousEpisode extends NativeTvIntent {
  const NativeTvPreviousEpisode();
}

/// « Plus tard » sur la proposition de l'épisode suivant.
final class NativeTvCancelAutoPlay extends NativeTvIntent {
  const NativeTvCancelAutoPlay();
}

final class NativeTvStartWatchParty extends NativeTvIntent {
  const NativeTvStartWatchParty();
}

final class NativeTvLeaveWatchParty extends NativeTvIntent {
  const NativeTvLeaveWatchParty();
}

/// Une réponse à une question ([NativeTvIds.questions]) : [answer] est l'une
/// des réponses `NativeTvIds.answer…`.
final class NativeTvAnswer extends NativeTvIntent {
  const NativeTvAnswer(this.question, this.answer);
  final String question;
  final String answer;
}

final class NativeTvSetRate extends NativeTvIntent {
  const NativeTvSetRate(this.rate);
  final double rate;
}

final class NativeTvSetFit extends NativeTvIntent {
  const NativeTvSetFit(this.mode);
  final VideoDisplayMode mode;
}

/// [auto] pour « Auto », sinon [key] : un barreau, ou null pour le Direct.
final class NativeTvSetQuality extends NativeTvIntent {
  const NativeTvSetQuality({this.key, this.auto = false});
  final String? key;
  final bool auto;
}

/// Une piste de la liste du serveur ([serverIndex]) ou du moteur
/// ([engineTrackId]), selon la liste que le menu a proposée.
final class NativeTvSetAudio extends NativeTvIntent {
  const NativeTvSetAudio({this.serverIndex, this.engineTrackId});
  final int? serverIndex;
  final String? engineTrackId;
}

/// La minuterie de veille : [episodes] ou [duration], ni l'un ni l'autre
/// pour l'arrêter.
final class NativeTvSetSleep extends NativeTvIntent {
  const NativeTvSetSleep({this.episodes, this.duration});
  final int? episodes;
  final Duration? duration;
}

/// Un chapitre choisi dans le menu de repli `chapters`, par son identifiant
/// (`VideoChapter.id`).
final class NativeTvJumpToChapter extends NativeTvIntent {
  const NativeTvJumpToChapter(this.chapterId);
  final int chapterId;
}

/// Un sous-titre choisi dans le menu AVKit, dans la numérotation du lecteur
/// (`PlaybackTrack.id`) : nul pour « aucun ».
final class NativeTvSetSubtitle extends NativeTvIntent {
  const NativeTvSetSubtitle(this.trackId);
  final String? trackId;
}

/// Lecture ou pause demandée dans AVKit, déjà appliquée par l'`AVPlayer` :
/// le lecteur l'annonce sans rappeler le moteur. [position] est en temps de
/// l'item.
final class NativeTvTransport extends NativeTvIntent {
  const NativeTvTransport({required this.playing, required this.position});
  final bool playing;
  final Duration position;
}

/// Une navigation de l'utilisateur dans AVKit (saut, balayage, chapitre),
/// déjà appliquée. En temps de l'item.
final class NativeTvUserSeeked extends NativeTvIntent {
  const NativeTvUserSeeked({required this.position, this.from});
  final Duration position;
  final Duration? from;
}

/// La même navigation, retenue par le natif (`interceptSeeks`) : c'est au
/// lecteur de chercher [position], en temps de l'item.
final class NativeTvSeekRequested extends NativeTvIntent {
  const NativeTvSeekRequested(this.position);
  final Duration position;
}

/// Quelqu'un se sert de la télécommande.
final class NativeTvUserActivity extends NativeTvIntent {
  const NativeTvUserActivity();
}

/// Une saison choisie dans le panneau des épisodes.
final class NativeTvSelectSeason extends NativeTvIntent {
  const NativeTvSelectSeason(this.seasonId);
  final int seasonId;
}

/// Un épisode choisi dans le panneau des épisodes (`Media.id`).
final class NativeTvOpenEpisode extends NativeTvIntent {
  const NativeTvOpenEpisode(this.mediaId);
  final int mediaId;
}

/// L'écran natif s'est fermé. [byUser] pour Menu sur la télécommande ; sinon
/// c'est l'app qui l'a demandé.
final class NativeTvClosed extends NativeTvIntent {
  const NativeTvClosed({required this.byUser});
  final bool byUser;
}

/// Le natif ne peut pas jouer ceci : l'écran Flutter reprend la main.
final class NativeTvUnavailable extends NativeTvIntent {
  const NativeTvUnavailable(this.reason);
  final OnyxAppleNativeReason? reason;
}

/// Une position du natif, en temps de l'item, sur la timeline du média : une
/// session HLS commence à [timelineOffset] et sa timeline repart de zéro.
Duration nativeTvAbsolute(Duration itemTime, Duration timelineOffset) =>
    itemTime + timelineOffset;

/// Traduit un événement natif, ou null pour un identifiant inconnu (un natif
/// plus récent que ce Dart) ou un champ manquant : il est ignoré plutôt que
/// mal compris.
NativeTvIntent? nativeTvIntentOf(OnyxAppleNativeEvent event) {
  switch (event.kind) {
    case OnyxAppleNativeEventKind.action:
      return _actionIntent(event.actionId);
    case OnyxAppleNativeEventKind.menuSelected:
      return _menuIntent(event.menuId, event.optionId);
    case OnyxAppleNativeEventKind.subtitleSelected:
      return NativeTvSetSubtitle(event.trackId);
    case OnyxAppleNativeEventKind.dismissed:
      return NativeTvClosed(
        byUser: event.reason != OnyxAppleNativeReason.requested,
      );
    case OnyxAppleNativeEventKind.unavailable:
      return NativeTvUnavailable(event.reason);
    case OnyxAppleNativeEventKind.transport:
      final playing = event.playing;
      final position = event.positionMs;
      if (playing == null || position == null) return null;
      return NativeTvTransport(
        playing: playing,
        position: Duration(milliseconds: position),
      );
    case OnyxAppleNativeEventKind.userSeeked:
      final position = event.positionMs;
      if (position == null) return null;
      final from = event.fromPositionMs;
      return NativeTvUserSeeked(
        position: Duration(milliseconds: position),
        from: from == null ? null : Duration(milliseconds: from),
      );
    case OnyxAppleNativeEventKind.seekRequested:
      final position = event.positionMs;
      if (position == null) return null;
      return NativeTvSeekRequested(Duration(milliseconds: position));
    case OnyxAppleNativeEventKind.panelRowSelected:
      return _panelRowIntent(event.panelId, event.rowId);
    case OnyxAppleNativeEventKind.panelTabSelected:
      return _panelTabIntent(event.panelId, event.optionId);
    case OnyxAppleNativeEventKind.userActivity:
      return const NativeTvUserActivity();
  }
}

NativeTvIntent? _actionIntent(String? actionId) {
  switch (actionId) {
    case null:
      return null;
    case NativeTvIds.skipSegment:
      return const NativeTvSkipSegment();
    case NativeTvIds.nextEpisode:
      return const NativeTvNextEpisode();
    case NativeTvIds.previousEpisode:
      return const NativeTvPreviousEpisode();
    case NativeTvIds.cancelAutoPlay:
      return const NativeTvCancelAutoPlay();
    case NativeTvIds.watchPartyStart:
      return const NativeTvStartWatchParty();
    case NativeTvIds.watchPartyLeave:
      return const NativeTvLeaveWatchParty();
  }
  final dot = actionId.indexOf('.');
  if (dot <= 0) return null;
  final question = actionId.substring(0, dot);
  if (!NativeTvIds.questions.contains(question)) return null;
  return NativeTvAnswer(question, actionId.substring(dot + 1));
}

NativeTvIntent? _panelRowIntent(String? panelId, String? rowId) {
  if (panelId != NativeTvIds.episodesPanel || rowId == null) return null;
  final id = _suffixInt(rowId, NativeTvIds.episodeRowPrefix);
  return id == null ? null : NativeTvOpenEpisode(id);
}

NativeTvIntent? _panelTabIntent(String? panelId, String? optionId) {
  if (panelId != NativeTvIds.episodesPanel || optionId == null) return null;
  final id = _suffixInt(optionId, NativeTvIds.seasonTabPrefix);
  return id == null ? null : NativeTvSelectSeason(id);
}

/// L'entier qui suit [prefix], ou null s'il n'y est pas.
int? _suffixInt(String value, String prefix) => value.startsWith(prefix)
    ? int.tryParse(value.substring(prefix.length))
    : null;

NativeTvIntent? _menuIntent(String? menuId, String? optionId) {
  if (optionId == null) return null;
  switch (menuId) {
    case NativeTvIds.speed:
      final rate = double.tryParse(optionId);
      return rate == null ? null : NativeTvSetRate(rate);
    case NativeTvIds.fit:
      final mode = VideoDisplayMode.values
          .where((mode) => mode.name == optionId)
          .firstOrNull;
      return mode == null ? null : NativeTvSetFit(mode);
    case NativeTvIds.quality:
      if (optionId == NativeTvIds.qualityAuto) {
        return const NativeTvSetQuality(auto: true);
      }
      if (optionId == NativeTvIds.qualityDirect) {
        return const NativeTvSetQuality();
      }
      if (optionId.startsWith(NativeTvIds.qualityTierPrefix)) {
        return NativeTvSetQuality(
          key: optionId.substring(NativeTvIds.qualityTierPrefix.length),
        );
      }
      return null;
    case NativeTvIds.audio:
      final index = _suffixInt(optionId, NativeTvIds.audioIndexPrefix);
      if (index != null) return NativeTvSetAudio(serverIndex: index);
      if (optionId.startsWith(NativeTvIds.audioTrackPrefix)) {
        return NativeTvSetAudio(
          engineTrackId:
              optionId.substring(NativeTvIds.audioTrackPrefix.length),
        );
      }
      return null;
    case NativeTvIds.sleep:
      if (optionId == NativeTvIds.sleepOff) return const NativeTvSetSleep();
      final episodes = _suffixInt(optionId, NativeTvIds.sleepEpisodesPrefix);
      if (episodes != null && episodes > 0) {
        return NativeTvSetSleep(episodes: episodes);
      }
      final minutes = _suffixInt(optionId, NativeTvIds.sleepMinutesPrefix);
      if (minutes != null && minutes > 0) {
        return NativeTvSetSleep(duration: Duration(minutes: minutes));
      }
      return null;
    case NativeTvIds.chapters:
      final chapter = _suffixInt(optionId, NativeTvIds.chapterPrefix);
      return chapter == null ? null : NativeTvJumpToChapter(chapter);
  }
  return null;
}
