import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_mode.dart';

/// Un bouton du pied d'un [OnyxDialog].
///
/// [primary] : l'action que le dialogue propose (capsule blanche, ou rouge
/// pleine si le dialogue est `destructive`). Sans, une capsule de verre.
/// [child] remplace le libellé (un indicateur de chargement, par exemple).
/// [onPressed] nul : le bouton est grisé.
class OnyxDialogAction {
  const OnyxDialogAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
    this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool autofocus;
  final Widget? child;
}

/// La fenêtre de dialogue d'Onyx (ADR-0128) : un seul cadre pour les
/// confirmations et les dialogues à contenu (champ, liste).
///
/// Sur TV, rend l'`AlertDialog` du thème comme avant : la TV a sa propre
/// refonte et garde ses boutons Material, qui portent déjà le focus
/// télécommande.
class OnyxDialog extends StatelessWidget {
  const OnyxDialog({
    super.key,
    required this.title,
    required this.actions,
    this.icon,
    this.destructive = false,
    this.message,
    this.content,
    this.width = 420,
  });

  final String title;

  /// Dans le disque de l'en-tête ; sans, pas de disque.
  final IconData? icon;

  /// Une suppression : disque et action principale en rouge.
  final bool destructive;

  /// Le texte d'une confirmation.
  final String? message;

  /// Le contenu d'un dialogue à champs ou à liste, sous le message.
  final Widget? content;
  final List<OnyxDialogAction> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (TvScope.of(context)) return _tvDialog();
    final accent = destructive ? AppColors.error : AppColors.textPrimary;
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  _IconDisc(
                    icon: icon!,
                    color: accent,
                    destructive: destructive,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppType.title3,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (message != null || content != null)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message != null)
                            Text(
                              message!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: AppType.body,
                                height: 1.5,
                              ),
                            ),
                          if (message != null && content != null)
                            const SizedBox(height: 16),
                          if (content != null) content!,
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                _ActionRow(actions: actions, destructive: destructive),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Le rendu d'avant, sur TV : l'`AlertDialog` du thème et ses boutons.
  Widget _tvDialog() {
    return AlertDialog(
      title: Text(title),
      scrollable: true,
      content: (message == null && content == null)
          ? null
          : SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message != null) Text(message!),
                  if (message != null && content != null)
                    const SizedBox(height: 16),
                  if (content != null) content!,
                ],
              ),
            ),
      actions: [
        for (final a in actions)
          if (a.primary && !destructive)
            FilledButton(
              autofocus: a.autofocus,
              onPressed: a.onPressed,
              child: a.child ?? Text(a.label),
            )
          else
            TextButton(
              autofocus: a.autofocus,
              onPressed: a.onPressed,
              style: a.primary
                  ? TextButton.styleFrom(foregroundColor: AppColors.error)
                  : null,
              child: a.child ?? Text(a.label),
            ),
      ],
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc({
    required this.icon,
    required this.color,
    required this.destructive,
  });

  final IconData icon;
  final Color color;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: destructive
            ? AppColors.error.withValues(alpha: 0.14)
            : AppColors.glassFill,
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}

/// Deux capsules de même largeur côte à côte ; trois ou plus s'empilent, car
/// des libellés longs ne tiennent pas à trois sur la largeur d'une fenêtre.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.actions, required this.destructive});

  final List<OnyxDialogAction> actions;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final a in actions) _Capsule(action: a, destructive: destructive),
    ];
    if (buttons.length > 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            buttons[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

class _Capsule extends StatefulWidget {
  const _Capsule({required this.action, required this.destructive});

  final OnyxDialogAction action;
  final bool destructive;

  @override
  State<_Capsule> createState() => _CapsuleState();
}

class _CapsuleState extends State<_Capsule> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final enabled = a.onPressed != null;
    final filled = a.primary;
    final base = !filled
        ? AppColors.glassFill
        : widget.destructive
        ? AppColors.error
        : AppColors.textPrimary;
    final foreground = !filled
        ? AppColors.textPrimary
        : widget.destructive
        ? Colors.white
        : AppColors.background;
    final fill = Color.alphaBlend(
      Colors.white.withValues(alpha: _hovered && enabled ? 0.08 : 0),
      base,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (v) => setState(() => _focused = v),
        child: AnimatedContainer(
          duration: AppMotion.fade(context, AppMotion.micro),
          curve: AppMotion.curve,
          height: 44,
          decoration: ShapeDecoration(
            color: enabled ? fill : fill.withValues(alpha: 0.4),
            shape: StadiumBorder(
              side: BorderSide(
                color: _focused
                    ? AppColors.focus
                    : filled
                    ? Colors.transparent
                    : AppColors.glassBorder,
                width: _focused ? 2 : 1,
              ),
            ),
          ),
          child: InkWell(
            autofocus: a.autofocus,
            customBorder: const StadiumBorder(),
            onTap: a.onPressed,
            onHover: (v) => setState(() => _hovered = v),
            child: Center(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: enabled
                      ? foreground
                      : foreground.withValues(alpha: 0.5),
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                ),
                child:
                    a.child ??
                    Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ouvre [builder] dans le cadre d'Onyx : même apparition partout
/// ([AppMotion]), Échap ou un clic à côté annulent.
Future<T?> showOnyxDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    animationStyle: AnimationStyle(
      duration: AppMotion.standard,
      reverseDuration: AppMotion.micro,
      curve: AppMotion.curve,
    ),
    builder: builder,
  );
}

/// Pose une question à deux issues. Rend vrai si l'utilisateur confirme, faux
/// s'il annule (bouton, Échap, clic à côté).
///
/// [destructive] : une suppression ou une perte — icône et action en rouge, et
/// le focus clavier démarre sur « Annuler », pour qu'Entrée ne supprime pas.
Future<bool> showOnyxConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showOnyxDialog<bool>(
    context: context,
    builder: (dialogContext) => OnyxDialog(
      title: title,
      message: message,
      icon: icon,
      destructive: destructive,
      actions: [
        OnyxDialogAction(
          label: cancelLabel ?? tr('Annuler'),
          autofocus: destructive,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        OnyxDialogAction(
          label: confirmLabel,
          primary: true,
          autofocus: !destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
