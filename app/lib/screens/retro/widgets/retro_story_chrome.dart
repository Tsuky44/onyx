import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_mode.dart';
import '../hooks/retro_story_controller.dart';

/// Ce qui se pose sur chaque écran du Rétro : les barres de progression, le
/// bouton pour fermer, les zones à toucher et, à la souris, les flèches.
///
/// Toucher à gauche revient, à droite avance ; maintenir met en pause tant
/// que le doigt reste. Un téléviseur passe par la télécommande (`RetroScreen`).
class RetroStoryChrome extends StatelessWidget {
  const RetroStoryChrome({
    super.key,
    required this.story,
    required this.ink,
    required this.year,
    required this.onClose,
  });

  final RetroStoryController story;

  /// L'encre de l'écran en cours : la barre se lit sur toutes les couleurs.
  final Color ink;
  final int year;
  final VoidCallback onClose;

  /// Un point touché, en part de l'écran : c'est de là que s'ouvre le cercle
  /// de l'écran suivant.
  static Offset? _fraction(BuildContext context, Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    return Offset(local.dx / box.size.width, local.dy / box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    final tv = TvScope.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _TapZone(
                story: story,
                onTapAt: (at) => story.previous(from: _fraction(context, at)),
              ),
            ),
            Expanded(
              flex: 7,
              child: _TapZone(
                story: story,
                onTapAt: (at) => story.next(from: _fraction(context, at)),
              ),
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProgressBars(story: story, ink: ink),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Rétro {0}', [year]),
                        style: TextStyle(
                          color: ink,
                          fontSize: AppType.footnote,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    if (story.paused)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(AppIcons.pause,
                            color: ink,
                            size: 16,
                            semanticLabel: tr('En pause')),
                      ),
                    if (!tv)
                      IconButton(
                        onPressed: onClose,
                        tooltip: tr('Fermer le Rétro'),
                        icon: Icon(AppIcons.close, color: ink),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // À la souris, des flèches au bord : sans elles, rien ne dit qu'un
        // clic sur la moitié gauche revient en arrière.
        if (!tv)
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth <= constraints.maxHeight) {
              return const SizedBox.shrink();
            }
            return Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _EdgeButton(
                    icon: AppIcons.back,
                    tooltip: tr('Écran précédent'),
                    ink: ink,
                    onPressed: story.previous,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _EdgeButton(
                    icon: AppIcons.chevronRight,
                    tooltip: tr('Écran suivant'),
                    ink: ink,
                    onPressed: story.next,
                  ),
                ),
              ],
            );
          }),
      ],
    );
  }
}

class _TapZone extends StatelessWidget {
  const _TapZone({required this.story, required this.onTapAt});
  final RetroStoryController story;

  /// Reçoit le point touché, en coordonnées de l'écran.
  final ValueChanged<Offset> onTapAt;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapUp: (details) => onTapAt(details.globalPosition),
        onLongPressStart: (_) => story.hold(),
        onLongPressEnd: (_) => story.release(),
        onLongPressCancel: story.release,
      );
}

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.story, required this.ink});
  final RetroStoryController story;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < story.count; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: ink.withValues(alpha: 0.28)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < story.index
                            ? 1
                            : i == story.index
                                ? story.progress.clamp(0.0, 1.0)
                                : 0,
                        child: ColoredBox(color: ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EdgeButton extends StatelessWidget {
  const _EdgeButton({
    required this.icon,
    required this.tooltip,
    required this.ink,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color ink;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          style: IconButton.styleFrom(
            backgroundColor: ink.withValues(alpha: 0.14),
            minimumSize: const Size(44, 44),
          ),
          icon: Icon(icon, color: ink),
        ),
      );
}
