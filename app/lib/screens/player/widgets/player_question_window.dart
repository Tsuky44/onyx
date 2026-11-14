import 'package:flutter/material.dart';

import '../../../theme/app_type.dart';
import '../../../tv/nav/tv_region.dart';
import '../../../tv/tv_mode.dart';
import '../../../utils/app_platform.dart';
import 'onyx/onyx_capsule_button.dart';
import 'onyx/onyx_chrome_theme.dart';
import 'onyx/onyx_glass_panel.dart';

/// Une réponse d'une [PlayerQuestionWindow].
class PlayerQuestionAnswer {
  const PlayerQuestionAnswer({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;

  /// La réponse est en cours d'exécution : elle tourne et n'est plus activable.
  final bool busy;
}

/// Une question que le lecteur pose par-dessus le film : une fenêtre de verre
/// au milieu de l'image voilée, la réponse attendue déjà sous la télécommande
/// (ADR-0130).
///
/// La même fenêtre pour « Vous regardez encore ? » et pour la lecture reprise
/// sur un autre appareil, qui étaient deux pages plein écran dessinées chacune
/// à sa façon. Elle n'agit jamais seule : pas de compte à rebours, une question
/// qui se répondrait toute seule ne protégerait pas celui qui dort.
class PlayerQuestionWindow extends StatefulWidget {
  const PlayerQuestionWindow({
    super.key,
    required this.title,
    required this.answers,
    this.message,
  }) : assert(answers.length > 0, 'une question a au moins une réponse');

  final String title;
  final String? message;

  /// La première est la réponse attendue : blanche, et sous la télécommande.
  final List<PlayerQuestionAnswer> answers;

  @override
  State<PlayerQuestionWindow> createState() => _PlayerQuestionWindowState();
}

class _PlayerQuestionWindowState extends State<PlayerQuestionWindow> {
  final FocusNode _entry = FocusNode(debugLabel: 'player-question-answer');

  @override
  void initState() {
    super.initState();
    // Demandé, pas `autofocus` : le lecteur tient déjà le focus, et un
    // autofocus ne le prend qu'à une portée où rien n'est focalisé. Sans cela
    // la télécommande n'aurait aucune réponse sous OK. Pas sur un écran tenu
    // en main : on y répond du doigt, et le focus y dessinerait un anneau que
    // nul n'a demandé.
    if (AppPlatform.isMobile && !TvMode.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entry.requestFocus();
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final answers = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.answers.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          OnyxControlsRow(
            child: OnyxCapsuleButton(
              key: ValueKey('player-question-answer-$i'),
              label: widget.answers[i].label,
              onPressed: widget.answers[i].onPressed,
              busy: widget.answers[i].busy,
              primary: i == 0,
              large: true,
              expanded: true,
              focusNode: i == 0 ? _entry : null,
            ),
          ),
        ],
      ],
    );
    final message = widget.message;
    return ColoredBox(
      color: OnyxChromeTheme.questionVeil,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: OnyxGlassPanel(
              radius: const BorderRadius.all(Radius.circular(22)),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 36, 36, 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: OnyxChromeTheme.title,
                          fontSize: AppType.title1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          height: 1.2,
                        ),
                      ),
                      if (message != null && message.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          message,
                          style: const TextStyle(
                            color: OnyxChromeTheme.time,
                            fontSize: AppType.callout,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      // Les réponses sont des rangées d'un seul bouton : Haut
                      // et Bas vont de l'une à l'autre et s'arrêtent là.
                      if (TvMode.isTv)
                        TvRegion.controlRows(child: answers)
                      else
                        answers,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
