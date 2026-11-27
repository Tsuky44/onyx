import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_type.dart';
import '../../../theme/retro_motion.dart';
import '../../../tv/tv_mode.dart';
import '../hooks/retro_story_controller.dart';
import 'retro_type.dart';

/// Ce qui se pose sur chaque écran du Rétro : les barres de progression, le
/// bouton pour fermer, les zones à toucher et, à la souris, les flèches.
///
/// Toucher à gauche revient, à droite avance ; maintenir met en pause tant
/// que le doigt reste, et le bouton pause garde l'écran affiché jusqu'à ce
/// qu'on le relance. Un téléviseur passe par la télécommande (`RetroScreen`).
///
/// Sur le dernier écran, deux boutons en bas : partager l'image de récap (ou
/// l'enregistrer, sur un PC) et revoir depuis le début. Pas au téléviseur.
class RetroStoryChrome extends StatelessWidget {
  const RetroStoryChrome({
    super.key,
    required this.story,
    required this.ink,
    required this.year,
    required this.onClose,
    this.muted = false,
    this.onToggleMute,
    this.background,
    this.onShare,
    this.sharing = false,
    this.shareSaves = false,
  });

  final RetroStoryController story;

  /// L'encre de l'écran en cours : la barre se lit sur toutes les couleurs.
  final Color ink;
  final int year;
  final VoidCallback onClose;
  final bool muted;
  final VoidCallback? onToggleMute;

  /// Le fond de l'écran en cours, pour écrire sur un bouton plein d'encre.
  final Color? background;

  /// Partage l'image de récap ; reçoit le bouton touché, en coordonnées de
  /// l'écran. Null : pas de bouton.
  final void Function(Rect origin)? onShare;

  /// L'image se prépare : le bouton attend.
  final bool sharing;

  /// Le bouton enregistre au lieu de partager (PC Windows ou Linux).
  final bool shareSaves;

  /// La carte du dernier écran est révélée (ou ne se joue pas) : les
  /// boutons de fin peuvent paraître. Elle dure le temps de l'écran.
  bool _endReady(BuildContext context) =>
      story.finished || story.progress >= 0.95 || RetroMotion.still(context);

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
    final onShare = this.onShare;
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
                    if (!tv && onToggleMute != null)
                      IconButton(
                        onPressed: onToggleMute,
                        tooltip: muted
                            ? tr('Rétablir le son')
                            : tr('Couper le son'),
                        icon: Icon(
                          muted ? AppIcons.volumeOff : AppIcons.volumeOn,
                          color: ink,
                        ),
                      ),
                    // Au doigt et à la souris, un bouton pour rester sur un
                    // écran le temps qu'on veut ; au téléviseur, la touche OK
                    // fait la même chose et seul le témoin s'affiche.
                    if (!tv)
                      IconButton(
                        onPressed: story.togglePause,
                        tooltip: story.paused
                            ? tr('Reprendre')
                            : tr('Mettre en pause'),
                        icon: Icon(
                          story.paused ? AppIcons.play : AppIcons.pause,
                          color: ink,
                        ),
                      )
                    else if (story.paused)
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
        if (!tv && story.isLast && onShare != null)
          // Sous le texte du dernier écran en paysage (à la marge des écrans
          // du Rétro), au pied de l'écran en portrait.
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final landscape = size.width > size.height;
                final u = RetroUnits.unitFor(size);
                return Align(
                  alignment:
                      landscape ? Alignment.bottomLeft : Alignment.bottomCenter,
                  child: Padding(
                    padding: landscape
                        ? EdgeInsets.only(left: u * 11, bottom: u * 7)
                        : const EdgeInsets.only(bottom: 20),
                    // Ils attendent que la carte du dernier écran soit
                    // révélée : avant, ils passeraient sur la carte.
                    child: AnimatedOpacity(
                      opacity: _endReady(context) ? 1 : 0,
                      duration: AppMotion.fade(context, AppMotion.reveal),
                      child: IgnorePointer(
                        ignoring: !_endReady(context),
                        child: _EndActions(
                          ink: ink,
                          background: background,
                          sharing: sharing,
                          shareSaves: shareSaves,
                          onShare: onShare,
                          onReplay: () => story.goTo(0),
                        ),
                      ),
                    ),
                  ),
                );
              },
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

/// Où est un widget à l'écran : la feuille de partage d'un iPad s'y accroche.
Rect _rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Les deux boutons du dernier écran : partager l'image (l'enregistrer, sur
/// un PC) et revoir depuis le début.
class _EndActions extends StatelessWidget {
  const _EndActions({
    required this.ink,
    required this.background,
    required this.sharing,
    required this.shareSaves,
    required this.onShare,
    required this.onReplay,
  });

  final Color ink;
  final Color? background;
  final bool sharing;
  final bool shareSaves;
  final void Function(Rect origin) onShare;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          Builder(
            builder: (button) => _ActionPill(
              icon: shareSaves ? AppIcons.download : AppIcons.share,
              label: shareSaves
                  ? tr('Enregistrer l’image')
                  : tr('Partager l’image'),
              ink: ink,
              background: background,
              busy: sharing,
              solid: true,
              onPressed: () => onShare(_rectOf(button)),
            ),
          ),
          _ActionPill(
            icon: AppIcons.replay,
            label: tr('Revoir'),
            ink: ink,
            background: background,
            onPressed: onReplay,
          ),
        ],
      );
}

/// Un bouton du dernier écran : plein d'encre pour l'action principale,
/// voilé pour l'autre.
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.ink,
    required this.onPressed,
    this.background,
    this.busy = false,
    this.solid = false,
  });

  final IconData icon;
  final String label;
  final Color ink;
  final Color? background;
  final VoidCallback onPressed;
  final bool busy;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final foreground = solid ? (background ?? const Color(0xFF000000)) : ink;
    return TextButton.icon(
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        backgroundColor: solid ? ink : ink.withValues(alpha: 0.16),
        foregroundColor: foreground,
        disabledBackgroundColor:
            (solid ? ink : ink.withValues(alpha: 0.16)).withValues(alpha: 0.6),
        disabledForegroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: AppType.body,
            fontWeight: FontWeight.w700),
      ),
      icon: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: foreground),
            )
          : Icon(icon, size: 18),
      label: Text(label),
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
