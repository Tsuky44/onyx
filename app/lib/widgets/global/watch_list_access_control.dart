// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/watch_list.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_focus.dart';
import 'onyx_menu.dart';

/// Ce qu'un compte peut faire d'une liste, tel que « Partager » le propose :
/// rien, la voir, ou la remplir (ADR-0127).
enum WatchListAccess {
  none,
  viewer,
  editor;

  static WatchListAccess of(WatchListMember? member) => switch (member?.role) {
        null => none,
        WatchListRole.viewer => viewer,
        WatchListRole.editor => editor,
      };

  /// La légende sous le nom de la personne.
  String get label => switch (this) {
        none => tr('Aucun accès'),
        viewer => tr('Peut voir'),
        editor => tr('Peut ajouter des titres'),
      };

  /// Le mot d'une case du choix en trois cases.
  String get short => switch (this) {
        none => tr('Aucun'),
        viewer => tr('Voir'),
        editor => tr('Ajouter'),
      };
}

/// Le choix de l'accès d'une personne en une rangée de cases, la case en
/// cours blanche à l'encre noire (ADR-0161) : un seul geste, sans ligne à
/// déplier. [choices] est la liste des issues que le serveur connaît (sans
/// « Voir » pour un serveur d'avant les rôles).
class WatchListAccessSegments extends StatelessWidget {
  const WatchListAccessSegments({
    super.key,
    required this.person,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.autofocus = false,
  });

  final String person;
  final WatchListAccess value;
  final List<WatchListAccess> choices;
  final ValueChanged<WatchListAccess> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: tr('Accès de {0}', [person]),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final access in choices)
              _Segment(
                label: access.short,
                tooltip: access.label,
                selected: access == value,
                autofocus: autofocus && access == value,
                onTap: () {
                  if (access != value) onChanged(access);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  static const _radius = BorderRadius.all(Radius.circular(15));

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: TvFocusable(
          onSelect: onTap,
          autofocus: autofocus,
          focusScale: 1.0,
          borderRadius: _radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              onTap: onTap,
              borderRadius: _radius,
              child: AnimatedContainer(
                duration: AppMotion.fade(context, AppMotion.micro),
                curve: AppMotion.curve,
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: _radius,
                  color: selected ? AppColors.focus : Colors.transparent,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.background
                        : AppColors.textSecondary,
                    fontSize: AppType.footnote,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

/// Le même choix sur un téléphone : une capsule qui dit l'accès et ouvre le
/// menu des issues, chacune avec ce qu'elle permet. Trois cases ne tiennent
/// pas à côté d'un nom sur la largeur d'un pouce.
class WatchListAccessChip extends StatefulWidget {
  const WatchListAccessChip({
    super.key,
    required this.person,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String person;
  final WatchListAccess value;
  final List<WatchListAccess> choices;
  final ValueChanged<WatchListAccess> onChanged;

  @override
  State<WatchListAccessChip> createState() => _WatchListAccessChipState();
}

class _WatchListAccessChipState extends State<WatchListAccessChip> {
  static String _detail(WatchListAccess access) => switch (access) {
        WatchListAccess.none => '',
        WatchListAccess.viewer => tr('La voit même quand elle est privée'),
        WatchListAccess.editor => tr('Y ajoute et en retire des titres'),
      };

  List<OnyxMenuItem<WatchListAccess>> get _items {
    final value = widget.value;
    return [
      for (final access in widget.choices.reversed)
        if (access != WatchListAccess.none)
          OnyxMenuItem(
            value: access,
            label: access.label,
            subtitle: _detail(access),
            checked: access == value,
          ),
      if (value != WatchListAccess.none)
        OnyxMenuItem(
          value: WatchListAccess.none,
          label: tr('Retirer l’accès'),
          destructive: true,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final invited = widget.value != WatchListAccess.none;
    final label = invited ? widget.value.label : tr('Inviter');
    return OnyxMenuButton<WatchListAccess>(
      tooltip: tr('Accès de {0}', [widget.person]),
      items: _items,
      onSelected: (access) {
        if (access != widget.value) widget.onChanged(access);
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          color: invited
              ? AppColors.accent.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: invited
                ? AppColors.accentMuted.withValues(alpha: 0.4)
                : AppColors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: invited
                      ? AppColors.accentMuted
                      : AppColors.textSecondary,
                  fontSize: AppType.subhead,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(AppIcons.expand,
                size: 16,
                color:
                    invited ? AppColors.accentMuted : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
