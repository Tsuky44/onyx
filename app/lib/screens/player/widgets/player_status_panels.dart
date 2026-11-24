// Les panneaux d'état du lecteur : ce qui remplace l'image quand elle ne
// vient pas, ou quand la lecture est ailleurs. Sortis de player_screen.dart.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../services/client_log.dart';
import '../playback/playback_session.dart';
import '../../../theme/app_type.dart';
import '../../../l10n/tr.dart';
import 'onyx/onyx_loading_ring.dart';
import 'player_question_window.dart';
import 'player_tv_scale.dart';

/// Le lecteur attend-il quelque chose : la première image, un changement de
/// qualité, un tampon vide ? Une seule réponse pour l'anneau d'attente
/// ([PlayerLoadingSpinner]) et pour le bouton lecture qui lui cède la place.
///
/// Une première image n'est pas un film qui joue : le moteur peut l'annoncer
/// avant que la lecture ne parte, et charger encore. Passé la première image,
/// c'est donc le moteur seul qui dit l'attente ([isBuffering]), que le
/// démarrage soit fini ou non.
///
/// Un démarrage qui a dépassé son délai ([startupStalled]) n'attend plus : il
/// a son panneau ([StalledStartup]), et un anneau n'a rien à faire dessus.
bool playerAwaitsPicture({
  required bool hasFirstFrame,
  required bool startupStalled,
  required bool isSwitchingQuality,
  required bool isBuffering,
}) {
  if (!hasFirstFrame) return !startupStalled;
  return isSwitchingQuality || isBuffering;
}

/// L'attente du lecteur : démarrage, recherche, changement de qualité.
///
/// Un anneau blanc ([OnyxLoadingRing], ADR-0140), au milieu de l'écran ou, sur
/// un écran tenu en main, là où est lecture/pause ([centreAt]) : il prend la
/// place du bouton au lieu de se poser dessous.
///
/// IgnorePointer, not AbsorbPointer: it covers the whole screen and sits above
/// the controls, so absorbing taps made every player button dead for as long
/// as a seek took to load. Loading is exactly when the user is most likely to
/// want to pause, seek again or go back, so the spinner has to be purely
/// decorative.
///
/// Sur un téléviseur ([isTv]), la couche se pose elle-même à l'échelle du
/// lecteur ([PlayerTvScale.layer]), comme tout ce qui est dessiné sur l'image.
///
/// Toujours posé par l'écran, qui dit seulement s'il attend ([visible]) :
/// l'anneau reste le temps de s'effacer, et garde son tour d'une attente à la
/// suivante.
class PlayerLoadingSpinner extends StatefulWidget {
  const PlayerLoadingSpinner({
    super.key,
    this.visible = true,
    this.isTv = false,
    this.centreAt = 0.5,
  });

  /// Le lecteur attend son image. Faux, l'anneau s'efface en fondu puis se
  /// démonte : sans attente, aucune animation ne tourne.
  final bool visible;

  final bool isTv;

  /// Où tombe son milieu, en fraction de la hauteur.
  final double centreAt;

  @override
  State<PlayerLoadingSpinner> createState() => _PlayerLoadingSpinnerState();
}

class _PlayerLoadingSpinnerState extends State<PlayerLoadingSpinner> {
  /// L'anneau est dans l'arbre : pendant l'attente, et le temps de son fondu
  /// de sortie.
  late bool _mounted = widget.visible;

  @override
  void didUpdateWidget(covariant PlayerLoadingSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) _mounted = true;
  }

  void _onGone() {
    if (!mounted || widget.visible) return;
    setState(() => _mounted = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return const SizedBox.shrink();
    const size = OnyxLoadingRing.defaultSize;
    return PlayerTvScale.layer(
      isTv: widget.isTv,
      child: Positioned.fill(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned(
                  left: (constraints.maxWidth - size) / 2,
                  top: constraints.maxHeight * widget.centreAt - size / 2,
                  child: OnyxLoadingRing(
                    present: widget.visible,
                    onGone: _onGone,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Standalone back control, shown while the end-of-season page hides the rest
/// of the player chrome. Kept independent of the HUD so it cannot be swept away
/// with it.
class PlayerBackButton extends StatefulWidget {
  final VoidCallback onTap;

  const PlayerBackButton({super.key, required this.onTap});

  @override
  State<PlayerBackButton> createState() => _PlayerBackButtonState();
}

class _PlayerBackButtonState extends State<PlayerBackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: _hovered ? 0.62 : 0.38),
            border: Border.all(
              color: _hovered ? Colors.white24 : Colors.white10,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: _hovered ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// La lecture a été reprise sur un autre appareil du compte : ce lecteur est
/// en pause et propose de la ramener ici.
class PlayingElsewhere extends StatelessWidget {
  final String deviceName;
  final bool busy;
  final VoidCallback onResume;
  final VoidCallback onBack;

  const PlayingElsewhere({
    super.key,
    required this.deviceName,
    required this.busy,
    required this.onResume,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return PlayerQuestionWindow(
      title: tr('Lecture en cours sur un autre appareil'),
      message: tr(
          'La lecture continue sur « {0} ». Reprenez-la ici, là où '
          'il en est.',
          [deviceName]),
      answers: [
        PlayerQuestionAnswer(
          label: tr('Reprendre la lecture ici'),
          onPressed: onResume,
          busy: busy,
        ),
        PlayerQuestionAnswer(label: tr('Quitter'), onPressed: onBack),
      ],
    );
  }
}

/// What replaces the start-up spinner once the picture is overdue.
///
/// The spinner is honest for twenty-five seconds and a lie after that: it says
/// "working on it" about a start-up that, by then, has usually stopped working
/// on anything. What actually helps is naming the likeliest cause — the link
/// between this screen and the server — and offering the one action that fixes
/// most of them, which is to open the whole thing again from scratch.
class StalledStartup extends StatelessWidget {
  /// Ce que le moteur a dit, quand il a dit quelque chose.
  ///
  /// Null veut dire que rien n'a échoué de façon visible et que c'est le délai
  /// de démarrage qui a parlé — le texte reste alors celui d'avant, qui nomme
  /// la cause la plus probable d'un démarrage qui n'aboutit pas.
  final PlaybackFailure? failure;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const StalledStartup({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onBack,
  });

  /// La phrase qui explique, choisie sur ce que le moteur a rapporté.
  String get _explanation => switch (failure?.kind) {
        PlaybackFailureKind.unsupported =>
          tr('Cet appareil ne sait pas décoder ce fichier, et le '
              'transcodage n’a pas pris le relais. Réessayer relance les '
              'deux.'),
        PlaybackFailureKind.source =>
          tr('Le serveur n’a pas pu livrer la vidéo. C’est presque toujours '
              'le réseau entre cet appareil et lui — réessayer suffit le '
              'plus souvent.'),
        PlaybackFailureKind.unknown =>
          tr('Le lecteur a renoncé sans que la cause soit claire. Réessayer '
              'suffit le plus souvent.'),
        null => tr('Le serveur met trop longtemps à envoyer la vidéo. C’est presque '
            'toujours le réseau entre cet appareil et lui — réessayer suffit '
            'le plus souvent.'),
      };

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.86),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_tethering_error_rounded,
                size: 54,
                color: Colors.white70,
              ),
              const SizedBox(height: 22),
              Text(
                tr('La lecture ne démarre pas'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppType.title2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _explanation,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: AppType.callout,
                  height: 1.45,
                ),
              ),
              // La ligne du moteur, telle quelle. Elle ne s'adresse pas au
              // spectateur mais à qui il enverra une capture d'écran : sans
              // elle, « ça ne se lance pas » reste la seule chose qu'on saura
              // d'une panne.
              if (failure != null) ...[
                const SizedBox(height: 14),
                Text(
                  failure!.message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: AppType.footnote,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    // The remote lands here: it is the button that helps.
                    autofocus: true,
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(tr('Réessayer')),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: onBack,
                    child: Text(tr('Retour')),
                  ),
                ],
              ),
              // Le journal, à l'endroit et au moment où on en a besoin.
              // L'aller chercher dans les réglages suppose de quitter l'écran,
              // ce qui est exactement le geste qui fait perdre le contexte de
              // la panne qu'on essaie de rapporter.
              const SizedBox(height: 10),
              _CopyLogButton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Copier le journal », avec sa confirmation sur place.
///
/// Un `StatefulWidget` pour la seule raison qu'un bouton qui ne dit rien après
/// un appui laisse croire qu'il n'a rien fait — et il n'y a pas de barre de
/// notification par-dessus le lecteur en plein écran.
class _CopyLogButton extends StatefulWidget {
  @override
  State<_CopyLogButton> createState() => _CopyLogButtonState();
}

class _CopyLogButtonState extends State<_CopyLogButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: ClientLog.export()));
        if (!mounted) return;
        setState(() => _copied = true);
      },
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 16,
        color: Colors.white54,
      ),
      label: Text(
        _copied ? tr('Journal copié') : tr('Copier le journal'),
        style: const TextStyle(color: Colors.white54, fontSize: AppType.subhead),
      ),
    );
  }
}
