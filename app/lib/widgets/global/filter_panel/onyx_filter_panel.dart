import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../onyx_panel_surface.dart';
import 'filter_presets.dart';
import 'onyx_filter_chip.dart';

/// Le panneau des filtres d'une grille (Demandes, bibliothèque) et ses
/// briques : une ligne de réglage sur place (le tri), des sections repliées
/// qui disent leur valeur, des capsules à cocher et des plages à choix
/// rapides. Les capsules sont celles de la rangée des Demandes, pour que
/// tout parle la même langue. Voir l'ADR du 2026-11-25.

/// Le cadre du panneau : l'en-tête (« Filtres », « Tout effacer », la
/// croix), un filet, puis [children] séparés par des filets.
///
/// Sur grand écran, il se pose dans `OnyxPanelSurface` (voir
/// `OnyxFilterDock`). Avec [sheet], il remplit une feuille du bas de
/// téléphone : la feuille donne le fond, la poignée et l'arrondi.
class OnyxFilterPanel extends StatelessWidget {
  const OnyxFilterPanel({
    super.key,
    required this.children,
    required this.onClose,
    this.onClearAll,
    this.sheet = false,
  });

  final List<Widget> children;
  final VoidCallback onClose;

  /// Nul tant qu'aucun filtre n'est posé : « Tout effacer » se retire.
  final VoidCallback? onClearAll;
  final bool sheet;

  /// Largeur sur grand écran : cinq tuiles de 52 px par rangée.
  static const double width = 340;

  @override
  Widget build(BuildContext context) {
    final onClearAll = this.onClearAll;
    final list = ListView(
      shrinkWrap: sheet,
      padding: EdgeInsets.only(
          bottom: sheet ? 16 + MediaQuery.paddingOf(context).bottom : 24),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const _Hairline(),
          children[i],
        ],
      ],
    );
    final content = Column(
      mainAxisSize: sheet ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, sheet ? 0 : 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('Filtres'),
                  style: const TextStyle(
                    fontSize: AppType.headline,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onClearAll != null)
                OnyxFilterLink(
                    label: tr('Tout effacer'), onPressed: onClearAll),
              IconButton(
                tooltip: tr('Fermer les filtres'),
                onPressed: onClose,
                icon: const Icon(AppIcons.close, size: 18),
              ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.glassBorder),
        if (sheet) Flexible(child: list) else Expanded(child: list),
      ],
    );
    if (sheet) {
      return ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: content,
      );
    }
    return OnyxPanelSurface(
      child: Material(type: MaterialType.transparency, child: content),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        color: AppColors.glassBorder,
      );
}

/// Le titre d'une ligne du panneau : le nom du filtre, en clair.
const _titleStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: AppType.body,
  fontWeight: FontWeight.w600,
);

/// Une ligne qui tient son réglage sur place, sans se déplier : le tri,
/// dont le menu Onyx se pose à droite du titre.
class OnyxFilterInlineRow extends StatelessWidget {
  const OnyxFilterInlineRow({
    super.key,
    required this.title,
    required this.trailing,
  });

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: _titleStyle)),
          trailing,
        ],
      ),
    );
  }
}

/// Un filtre du panneau, replié à l'ouverture : son titre, sa valeur en
/// dessous (« Toutes », « Action, Drame », en blanc dès qu'il est posé), un
/// « Effacer » quand il est posé et un chevron. Toucher l'en-tête déplie le
/// choix ; tout montrer d'un coup faisait un panneau fouillis.
class OnyxFilterSection extends StatefulWidget {
  const OnyxFilterSection({
    super.key,
    required this.title,
    required this.value,
    required this.active,
    required this.onClear,
    required this.child,
  });

  final String title;
  final String value;
  final bool active;
  final VoidCallback onClear;
  final Widget child;

  @override
  State<OnyxFilterSection> createState() => _OnyxFilterSectionState();
}

class _OnyxFilterSectionState extends State<OnyxFilterSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: _titleStyle),
                        const SizedBox(height: 2),
                        Text(
                          widget.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.subhead,
                            color: active
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (active)
                    OnyxFilterLink(
                        label: tr('Effacer'), onPressed: widget.onClear),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: AppMotion.move(context, AppMotion.micro),
                    curve: AppMotion.curve,
                    child: const Icon(AppIcons.expand,
                        size: 16, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.move(context),
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Un lien discret du panneau (« Effacer », « Dates précises »…) : du texte
/// secondaire sans cadre, qui ne pèse pas plus que le titre qu'il suit.
class OnyxFilterLink extends StatelessWidget {
  const OnyxFilterLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.expanded,
  });

  final String label;
  final VoidCallback onPressed;

  /// Non nul : le lien ouvre ou ferme un bloc, et son chevron le dit.
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(
        fontSize: AppType.footnote,
        fontWeight: FontWeight.w600,
      ),
    );
    final expanded = this.expanded;
    if (expanded == null) {
      return TextButton(onPressed: onPressed, style: style, child: Text(label));
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: style,
      iconAlignment: IconAlignment.end,
      icon: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: AppMotion.move(context, AppMotion.micro),
        curve: AppMotion.curve,
        child: const Icon(AppIcons.expand, size: 14),
      ),
      label: Text(label),
    );
  }
}

/// Des capsules qui se cochent sur place, sans chevron : rien ne s'ouvre.
class OnyxFilterPills extends StatelessWidget {
  const OnyxFilterPills({super.key, required this.choices});

  final List<({String label, bool selected, VoidCallback onTap})> choices;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in choices)
          Semantics(
            selected: c.selected,
            child: OnyxFilterChip(
              label: c.label,
              active: c.selected,
              chevron: false,
              onTap: c.onTap,
            ),
          ),
      ],
    );
  }
}

/// Une plage (période, durée) : des choix rapides en capsules et, avec
/// [fields], les deux champs exacts derrière le lien [customLabel]. Les
/// champs s'ouvrent d'eux-mêmes quand la plage posée ne correspond à aucun
/// choix rapide.
class OnyxFilterRange extends StatefulWidget {
  const OnyxFilterRange({
    super.key,
    required this.presets,
    required this.from,
    required this.to,
    required this.onChanged,
    this.customLabel,
    this.fields,
  });

  final List<FilterRangePreset> presets;
  final String from;
  final String to;
  final void Function(String from, String to) onChanged;
  final String? customLabel;

  /// Les deux champs, déjà branchés par le panneau qui tient leurs
  /// contrôleurs. Nul : les choix rapides seuls.
  final Widget? fields;

  @override
  State<OnyxFilterRange> createState() => _OnyxFilterRangeState();
}

class _OnyxFilterRangeState extends State<OnyxFilterRange> {
  bool _custom = false;

  @override
  Widget build(BuildContext context) {
    final current = matchingPreset(widget.presets, widget.from, widget.to);
    final hasValue = widget.from.isNotEmpty || widget.to.isNotEmpty;
    final showFields = _custom || (hasValue && current == null);
    final fields = widget.fields;
    final pills = OnyxFilterPills(choices: [
      for (final p in widget.presets)
        (
          label: p.label,
          selected: identical(p, current),
          // Une capsule allumée ne se rallume pas : la toucher retire la
          // plage, comme le ✕ des capsules du haut.
          onTap: () => identical(p, current)
              ? widget.onChanged('', '')
              : widget.onChanged(p.from, p.to),
        ),
    ]);
    if (fields == null) return pills;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pills,
        const SizedBox(height: 6),
        OnyxFilterLink(
          label: widget.customLabel ?? '',
          expanded: showFields,
          onPressed: () => setState(() => _custom = !showFields),
        ),
        AnimatedSize(
          duration: AppMotion.move(context),
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: showFields
              ? Padding(padding: const EdgeInsets.only(top: 8), child: fields)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
