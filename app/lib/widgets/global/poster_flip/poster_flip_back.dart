import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../tv/nav/tv_focusable.dart';
import '../../../tv/nav/tv_region.dart';
import '../glass_chrome.dart' show glassBlurs;
import '../progress_pill.dart';

/// Une action du dos de l'affiche.
class PosterFlipAction<T> {
  const PosterFlipAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;

  /// Retire quelque chose (« Supprimer de Reprendre ») : teintée d'erreur,
  /// pour qu'on ne la prenne pas pour une action sans conséquence.
  final bool destructive;
}

/// Le dos d'une affiche retournée : l'affiche floutée sous un voile, le titre,
/// où l'on en est, puis les actions.
class PosterFlipBack<T> extends StatelessWidget {
  const PosterFlipBack({
    super.key,
    required this.poster,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.actions,
    required this.borderRadius,
    required this.onSelected,
    this.onClose,
  });

  final Widget poster;
  final String title;
  final String? subtitle;
  final double? progress;
  final List<PosterFlipAction<T>> actions;
  final BorderRadius borderRadius;
  final ValueChanged<T> onSelected;

  /// Hors téléviseur, un bouton retour en haut à droite referme la carte :
  /// à la souris ou au doigt, il n'y a pas de touche retour pour le faire.
  /// Nul sur un téléviseur, où la télécommande a la sienne.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final blurs = glassBlurs(context);
    final progress = this.progress;
    final subtitle = this.subtitle;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Le dos garde les couleurs de son affiche : c'est la même carte.
          // Un flou d'image, pas de fond (`BackdropFilter`) : il ne relit rien
          // de dessous, et la rotation ne le refait pas à chaque image.
          if (blurs)
            RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Transform.scale(scale: 1.25, child: poster),
              ),
            )
          else
            poster,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: blurs ? 0.62 : 0.8),
                  AppColors.background.withValues(alpha: blurs ? 0.86 : 0.94),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  // Le titre ne passe pas sous le bouton retour.
                  padding: EdgeInsets.only(right: onClose == null ? 0 : 30),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.callout,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.caption,
                      height: 1.3,
                    ),
                  ),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 10),
                  ProgressPill(value: progress.clamp(0.0, 1.0)),
                ],
                const Spacer(),
                TvRegion.list(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: 4),
                        _ActionTile(
                          action: actions[i],
                          first: i == 0,
                          onSelected: () => onSelected(actions[i].value),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            Positioned(
              top: 8,
              right: 8,
              child: _CloseButton(onPressed: onClose!),
            ),
        ],
      ),
    );
  }
}

/// Le bouton retour du dos, hors téléviseur : un rond discret qui s'éclaire
/// au survol, comme les actions.
class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fade = AppMotion.fade(context, AppMotion.micro);
    return Semantics(
      button: true,
      label: tr('Retour'),
      excludeSemantics: true,
      child: Tooltip(
        message: tr('Retour'),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: fade,
              curve: AppMotion.curve,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovered
                    ? AppColors.textPrimary
                    : Colors.white.withValues(alpha: 0.12),
              ),
              child: Icon(
                AppIcons.back,
                size: 15,
                color: _hovered ? AppColors.background : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une ligne d'action. Le focus la remplit de blanc, comme les menus de
/// l'Apple TV : lisible de trois mètres, sans anneau de plus sur la carte.
class _ActionTile<T> extends StatefulWidget {
  const _ActionTile({
    required this.action,
    required this.first,
    required this.onSelected,
  });

  final PosterFlipAction<T> action;
  final bool first;
  final VoidCallback onSelected;

  @override
  State<_ActionTile<T>> createState() => _ActionTileState<T>();
}

class _ActionTileState<T> extends State<_ActionTile<T>> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit = _focused || _hovered;
    final action = widget.action;
    final tint = action.destructive ? AppColors.error : AppColors.textPrimary;
    final foreground = lit
        ? (action.destructive ? AppColors.error : AppColors.background)
        : tint;
    final fade = AppMotion.fade(context, AppMotion.micro);

    return TvFocusable(
      onSelect: widget.onSelected,
      // La première action reçoit le focus à l'ouverture : la télécommande
      // est déjà dans le menu quand l'affiche finit de tourner.
      autofocus: widget.first,
      entry: widget.first,
      focusScale: 1.0,
      showRing: false,
      borderRadius: BorderRadius.circular(10),
      onFocusChange: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      child: Semantics(
        button: true,
        label: action.label,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelected,
            child: AnimatedContainer(
              duration: fade,
              curve: AppMotion.curve,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: lit
                    ? AppColors.textPrimary
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(action.icon, size: 16, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: fade,
                      curve: AppMotion.curve,
                      style: TextStyle(
                        color: foreground,
                        fontSize: AppType.footnote,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                      child: Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
