import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../utils/responsive.dart';

/// Un message bref dans la matière des menus (ADR-0161) : une capsule sombre
/// au filet de verre, son icône, et au plus une action (« Annuler »). Il
/// passe par le `ScaffoldMessenger` comme une SnackBar : même file d'attente,
/// même durée, même annonce aux lecteurs d'écran ; seul le dessin change.
///
/// [error] : un échec, en rouge. [duration] : six secondes pour un retrait
/// qui se défait (ADR-0160 §6), le défaut sinon.
void showOnyxToast(
  BuildContext context,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  showOnyxToastOn(
    ScaffoldMessenger.of(context),
    message,
    error: error,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
  );
}

/// [showOnyxToast] sur un messager déjà pris : après un `await`, le contexte
/// de l'écran a pu partir, le messager de l'app reste.
void showOnyxToastOn(
  ScaffoldMessengerState messenger,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final wide = !AppLayout.isCompact(messenger.context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: duration ?? const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      width: wide ? 480 : null,
      content: _ToastBody(
        message: message,
        error: error,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                messenger.hideCurrentSnackBar();
                onAction();
              },
      ),
    ));
}

class _ToastBody extends StatelessWidget {
  const _ToastBody({
    required this.message,
    required this.error,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final action = onAction;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.fromLTRB(18, 6, label != null ? 6 : 18, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: error
              ? AppColors.error.withValues(alpha: 0.5)
              : AppColors.glassBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(error ? AppIcons.error : AppIcons.check,
              size: 18, color: error ? AppColors.error : AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppType.body,
                height: 1.35,
              ),
            ),
          ),
          if (label != null && action != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: action,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(
                    fontSize: AppType.body, fontWeight: FontWeight.w600),
              ),
              child: Text(label),
            ),
          ],
        ],
      ),
    );
  }
}
