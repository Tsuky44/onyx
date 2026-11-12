import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../theme/focus_fill.dart';
import '../../../tv/tv_mode.dart';
import 'settings_ui.dart' show SettingsIcon;

/// Une ligne de réglage : un titre, une explication, et à droite sa valeur ou
/// sa commande.
///
/// Sur téléviseur, la ligne visée se remplit de blanc et son texte passe au
/// noir, comme toute commande ([FocusFill], ADR-0112 étendue par l'ADR-0118) :
/// le voile bleu de 16 % ne se voyait pas du canapé. Ce qui est à droite est
/// le widget de l'appelant, avec ses propres couleurs claires : il est repeint
/// en encre d'un seul bloc ([_inked]), sauf un interrupteur, dont la couleur
/// dit l'état.
class SettingsTile extends StatefulWidget {
  const SettingsTile({
    super.key,
    this.icon,
    this.iconColor,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron,
  });

  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool? showChevron;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  final FocusNode _node = FocusNode(debugLabel: 'settings-tile');
  bool _focused = false;

  /// Ce qui est à droite garde son état quand le remplissage l'enveloppe :
  /// sans clé, un menu ou une roue d'attente renaîtrait à chaque focus.
  final GlobalKey _trailingKey = GlobalKey();
  final GlobalKey _leadingKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _node
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  /// La ligne elle-même, pas ce qu'elle contient : quand la télécommande est
  /// sur son menu ou son bouton, c'est lui qui montre le focus. La ligne ne
  /// doit alors ni se remplir ni envelopper ce widget, qui le perdrait.
  void _onFocusChanged() {
    final focused = _node.hasPrimaryFocus;
    if (_focused != focused) setState(() => _focused = focused);
  }

  /// Le widget de l'appelant, repeint en encre : ses textes et ses icônes
  /// gris clair seraient illisibles sur le blanc du focus.
  Widget _inked(Widget child) => ColorFiltered(
        colorFilter: const ColorFilter.mode(FocusFill.ink, BlendMode.srcIn),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final trailing = widget.trailing;
    final chevron =
        widget.showChevron ?? (widget.onTap != null && trailing == null);
    final filled = _focused && TvScope.of(context);
    final titleColor = filled
        ? FocusFill.ink
        : widget.destructive
            ? AppColors.error
            : AppColors.textPrimary;
    return InkWell(
      onTap: widget.onTap,
      focusNode: _node,
      focusColor: TvScope.of(context)
          ? FocusFill.fill
          : AppColors.primary.withValues(alpha: 0.16),
      hoverColor: Colors.white.withValues(alpha: 0.03),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: LayoutBuilder(builder: (context, constraints) {
            final stackControl = constraints.maxWidth < 440 &&
                trailing != null &&
                trailing is! Switch;
            final keyed = trailing == null
                ? null
                : KeyedSubtree(key: _trailingKey, child: trailing);
            final control = keyed == null
                ? null
                : filled && trailing is! Switch
                    ? _inked(keyed)
                    : keyed;
            return Row(
              children: [
                if (widget.leading != null)
                  filled
                      ? _inked(KeyedSubtree(
                          key: _leadingKey, child: widget.leading!))
                      : KeyedSubtree(key: _leadingKey, child: widget.leading!)
                else if (widget.icon != null)
                  SettingsIcon(
                    widget.icon!,
                    color: filled
                        ? FocusFill.ink
                        : widget.destructive
                            ? AppColors.error
                            : widget.iconColor,
                  ),
                if (widget.leading != null || widget.icon != null)
                  const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.w600,
                          fontSize: AppType.callout,
                        ),
                      ),
                      if (widget.subtitle != null &&
                          widget.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle!,
                          style: TextStyle(
                            color: filled
                                ? FocusFill.ink.withValues(alpha: 0.72)
                                : AppColors.textSecondary,
                            fontSize: AppType.subhead,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (stackControl) ...[
                        const SizedBox(height: 12),
                        control!,
                      ],
                    ],
                  ),
                ),
                if (control != null && !stackControl) ...[
                  const SizedBox(width: 12),
                  control,
                ],
                if (chevron) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      color: filled ? FocusFill.ink : AppColors.textMuted,
                      size: 20),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}
