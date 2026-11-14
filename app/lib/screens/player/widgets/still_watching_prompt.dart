import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import 'player_question_window.dart';

/// « Vous regardez encore ? » : ce qui prend l'écran quand plusieurs épisodes
/// se sont enchaînés sans que personne ne touche au lecteur (ADR-0045).
///
/// La lecture est en pause dessous et n'en sort que par une réponse. Il n'y a
/// pas de compte à rebours : une question qui se répondrait toute seule ne
/// protégerait pas celui qui dort.
class StillWatchingPrompt extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onLeave;

  const StillWatchingPrompt({
    super.key,
    required this.onContinue,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return PlayerQuestionWindow(
      title: tr('Vous regardez encore ?'),
      message: tr('Plusieurs épisodes se sont enchaînés sans que personne '
          'ne touche au lecteur. La lecture est en pause.'),
      answers: [
        PlayerQuestionAnswer(
          label: tr('Continuer la lecture'),
          onPressed: onContinue,
        ),
        PlayerQuestionAnswer(label: tr('Quitter'), onPressed: onLeave),
      ],
    );
  }
}
