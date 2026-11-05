import 'package:onyx_player_apple/onyx_player_apple.dart';

import 'native_tv_contract.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import 'audio_language_gap.dart';
import 'native_tv_spec.dart';

/// La question que l'interface Onyx poserait par une carte ou un panneau, et
/// que l'écran natif pose par une alerte (`UIAlertController`).
///
/// Une seule à la fois : l'écran choisit laquelle, dans l'ordre où l'interface
/// Onyx les empile.
sealed class NativeTvQuestion {
  const NativeTvQuestion();
}

/// « Vous regardez encore ? » (`StillWatchingPrompt`).
final class NativeTvStillWatchingQuestion extends NativeTvQuestion {
  const NativeTvStillWatchingQuestion();
}

/// La lecture est passée sur un autre appareil (`PlayingElsewhere`).
final class NativeTvPlayingElsewhereQuestion extends NativeTvQuestion {
  const NativeTvPlayingElsewhereQuestion(this.deviceName);
  final String deviceName;
}

/// L'épisode n'existe pas dans la langue suivie (`LanguageGapOverlay`) :
/// celui qu'on lance ([atLaunch]) ou le suivant.
final class NativeTvLanguageQuestion extends NativeTvQuestion {
  const NativeTvLanguageQuestion(this.gap, {required this.atLaunch});
  final AudioLanguageGap gap;
  final bool atLaunch;
}

/// La saison suivante n'est pas sur le serveur (`NextSeasonOverlay`).
/// [canPlayNext] quand un dernier épisode la précède encore.
final class NativeTvNextSeasonQuestion extends NativeTvQuestion {
  const NativeTvNextSeasonQuestion(this.season, {required this.canPlayNext});
  final NextSeason season;
  final bool canPlayNext;
}

/// L'épisode suivant n'est pas encore sorti (`UpcomingEpisodeOverlay`).
final class NativeTvUpcomingQuestion extends NativeTvQuestion {
  const NativeTvUpcomingQuestion(this.episode, {required this.canPlayNext});
  final UpcomingEpisode episode;
  final bool canPlayNext;
}

/// Les alertes, avec les textes des cartes Onyx. Menu (la touche Retour) vaut
/// ce que vaut Retour dans l'interface Onyx : quitter devant « Vous regardez
/// encore ? » et la lecture passée ailleurs, ranger la carte sinon.
abstract final class NativeTvQuestions {
  const NativeTvQuestions._();

  static OnyxAppleNativePrompt prompt(NativeTvQuestion question) =>
      switch (question) {
        NativeTvStillWatchingQuestion() => _prompt(
            NativeTvIds.stillWatching,
            title: tr('Vous regardez encore ?'),
            message:
                tr('Plusieurs épisodes se sont enchaînés sans que personne '
                    'ne touche au lecteur. La lecture est en pause.'),
            answers: [
              (NativeTvIds.answerContinue, tr('Continuer la lecture')),
              (NativeTvIds.answerLeave, tr('Quitter')),
            ],
            cancel: NativeTvIds.answerLeave,
          ),
        NativeTvPlayingElsewhereQuestion(:final deviceName) => _prompt(
            NativeTvIds.playingElsewhere,
            title: tr('Lecture en cours sur un autre appareil'),
            message: tr(
                'La lecture continue sur « {0} ». Reprenez-la ici, là où '
                'il en est.',
                [deviceName]),
            answers: [
              (NativeTvIds.answerResume, tr('Reprendre la lecture ici')),
              (NativeTvIds.answerLeave, tr('Quitter')),
            ],
            cancel: NativeTvIds.answerLeave,
          ),
        NativeTvLanguageQuestion(:final gap, :final atLaunch) =>
          _language(gap, atLaunch: atLaunch),
        NativeTvNextSeasonQuestion(:final season, :final canPlayNext) =>
          _nextSeason(season, canPlayNext: canPlayNext),
        NativeTvUpcomingQuestion(:final episode, :final canPlayNext) => _prompt(
            NativeTvIds.upcomingEpisode,
            title: episode.name.isNotEmpty
                ? episode.name
                : tr('Épisode {0}', [episode.number]),
            message: _upcomingDescription(episode),
            answers: [
              if (canPlayNext)
                (NativeTvIds.answerPlayNext, tr('Épisode suivant')),
              (NativeTvIds.answerDismiss, tr('Fermer')),
            ],
            cancel: NativeTvIds.answerDismiss,
          ),
      };

  static OnyxAppleNativePrompt _language(
    AudioLanguageGap gap, {
    required bool atLaunch,
  }) {
    final wanted = languageNameInSentence(gap.wanted);
    final offered = languageNameInSentence(gap.offered);
    return _prompt(
      atLaunch ? NativeTvIds.launchLanguageGap : NativeTvIds.languageGap,
      title: atLaunch
          ? tr('Cet épisode n’est pas disponible en {0}.', [wanted])
          : tr('L’épisode suivant n’est pas disponible en {0}.', [wanted]),
      message: tr(
        'Voulez-vous le regarder en {0} ? Si vous préférez attendre, la '
        'série reviendra dans « Reprendre la lecture » dès que l’épisode sera '
        'disponible en {1}.',
        [offered, wanted],
      ),
      answers: [
        (NativeTvIds.answerContinue, tr('Continuer en {0}', [offered])),
        (NativeTvIds.answerWait, tr('Attendre la version en {0}', [wanted])),
        (NativeTvIds.answerDismiss, tr('Fermer')),
      ],
      cancel: NativeTvIds.answerDismiss,
    );
  }

  static OnyxAppleNativePrompt _nextSeason(
    NextSeason season, {
    required bool canPlayNext,
  }) {
    return _prompt(
      NativeTvIds.nextSeason,
      title: season.name.isNotEmpty
          ? season.name
          : tr('Saison {0}', [season.number]),
      message: _seasonDescription(season, lookahead: canPlayNext),
      answers: [
        if (season.canRequest)
          (
            NativeTvIds.answerRequest,
            tr('Demander la saison {0}', [season.number]),
          ),
        if (canPlayNext) (NativeTvIds.answerPlayNext, tr('Épisode suivant')),
        (
          NativeTvIds.answerDismiss,
          season.canRequest ? tr('Non merci') : tr('Fermer'),
        ),
      ],
      cancel: NativeTvIds.answerDismiss,
    );
  }

  /// Le texte de `NextSeasonOverlay`, mot pour mot.
  static String _seasonDescription(NextSeason season,
      {required bool lookahead}) {
    if (season.isRequested) {
      return lookahead
          ? tr('Demande envoyée. Le téléchargement se lance pendant que tu '
              'termines l’épisode en cours.')
          : tr('Cette saison a déjà été demandée. Elle apparaîtra dans ta '
              'bibliothèque dès qu’elle sera disponible.');
    }
    if (lookahead) {
      return tr(
          'Il ne reste plus qu’un épisode disponible, et la saison {0} n’est '
          'pas sur le serveur. La demander maintenant lui laisse le temps de '
          'se télécharger pendant que tu le regardes.',
          [season.number]);
    }
    if (season.overview?.isNotEmpty == true) return season.overview!;
    return tr('Cette saison n’est pas encore sur le serveur.');
  }

  /// Le texte de `UpcomingEpisodeOverlay`, mot pour mot.
  static String _upcomingDescription(UpcomingEpisode episode) {
    if (episode.overview?.isNotEmpty == true) return episode.overview!;
    if (episode.isUnaired) {
      return tr(
          'Cet épisode n’est pas encore sorti. Il rejoindra le serveur peu '
          'après sa diffusion.');
    }
    return tr('Cet épisode est sorti mais n’est pas encore sur le serveur. Il '
        'arrivera dès qu’il aura été récupéré.');
  }

  static OnyxAppleNativePrompt _prompt(
    String id, {
    required String title,
    String? message,
    required List<(String, String)> answers,
    required String cancel,
  }) =>
      OnyxAppleNativePrompt(
        id: id,
        title: title,
        message: message,
        actions: [
          for (final (answer, label) in answers)
            OnyxAppleNativeAction(
              id: NativeTvIds.answer(id, answer),
              label: label,
            ),
        ],
        cancelActionId: NativeTvIds.answer(id, cancel),
      );
}
