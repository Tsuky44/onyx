import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/nav/tv_focusable.dart';
import '../../utils/responsive.dart';
import 'onyx_menu.dart';
import 'onyx_panel_surface.dart';

/// Les mesures du panneau d'[OnyxMenuButton]. Les lignes ont une hauteur
/// fixe : la route en déduit la hauteur du panneau avant de le poser (dessus
/// ou dessous le bouton) et le défilement initial d'une longue liste, sans
/// attendre une passe de mise en page.
class OnyxMenuMetrics {
  const OnyxMenuMetrics({required this.compact});

  /// Pour un écran étroit, tenu au doigt : des lignes plus hautes.
  final bool compact;

  factory OnyxMenuMetrics.of(BuildContext context) => OnyxMenuMetrics(
        compact: MediaQuery.sizeOf(context).width < AppBreakpoints.compact,
      );

  static const double padding = 6;
  static const double radius = OnyxPanelSurface.radius;
  static const double minWidth = 200;
  static const double maxWidth = 320;

  /// Le filet qui sépare les lignes destructives, marges comprises.
  static const double hairline = 9;

  double rowHeight(OnyxMenuItem<Object?> item) =>
      (compact ? 44 : 40) + (item.subtitle == null ? 0 : 14);

  /// Un filet avant la première ligne destructive qui suit une ligne
  /// ordinaire.
  static bool hairlineBefore(List<OnyxMenuItem<Object?>> items, int index) =>
      index > 0 && items[index].destructive && !items[index - 1].destructive;

  /// Le haut de la ligne [index] dans le contenu défilant, padding compris.
  double offsetOf(List<OnyxMenuItem<Object?>> items, int index) {
    var y = padding;
    for (var i = 0; i < index; i++) {
      if (hairlineBefore(items, i)) y += hairline;
      y += rowHeight(items[i]);
    }
    if (index < items.length && hairlineBefore(items, index)) y += hairline;
    return y;
  }

  /// La hauteur naturelle du panneau, sans plafond d'écran.
  /// Le filet `glassBorder` du panneau, en haut et en bas, compte aussi.
  double heightOf(List<OnyxMenuItem<Object?>> items) =>
      2 + offsetOf(items, items.length) + padding;
}

/// Le panneau : les lignes de [items] dans la matière du menu du compte.
/// [onPick] reçoit l'indice de la ligne choisie.
class OnyxMenuPanel<T> extends StatefulWidget {
  const OnyxMenuPanel({
    super.key,
    required this.items,
    required this.metrics,
    required this.onPick,
    this.focusFirst = false,
  });

  final List<OnyxMenuItem<T>> items;
  final OnyxMenuMetrics metrics;
  final ValueChanged<int> onPick;

  /// Ouvert au clavier : la ligne cochée (ou la première) prend le focus.
  /// À la souris, aucune ligne n'est allumée avant d'être survolée.
  final bool focusFirst;

  @override
  State<OnyxMenuPanel<T>> createState() => _OnyxMenuPanelState<T>();
}

class _OnyxMenuPanelState<T> extends State<OnyxMenuPanel<T>> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _initialFocus = FocusNode(debugLabel: 'OnyxMenu.initial');
  late final int _initialIndex;

  @override
  void initState() {
    super.initState();
    final checked = widget.items.indexWhere((i) => i.checked);
    final firstEnabled = widget.items.indexWhere((i) => i.enabled);
    _initialIndex = checked >= 0 ? checked : firstEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
  }

  /// Défile sur la ligne cochée, centrée, et donne le focus au clavier.
  /// `TvFocusable.autofocus` ne vaut que sur un téléviseur : le focus se
  /// demande ici.
  void _settle() {
    if (!mounted) return;
    final checked = widget.items.indexWhere((i) => i.checked);
    if (checked >= 0 && _scroll.hasClients) {
      final position = _scroll.position;
      final row = widget.metrics.rowHeight(widget.items[checked]);
      final target = widget.metrics.offsetOf(widget.items, checked) -
          (position.viewportDimension - row) / 2;
      _scroll.jumpTo(target.clamp(0, position.maxScrollExtent));
    }
    if (widget.focusFirst && _initialIndex >= 0) _initialFocus.requestFocus();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _initialFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final choice = items.any((i) => i.checked);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: OnyxMenuMetrics.minWidth,
        maxWidth: OnyxMenuMetrics.maxWidth,
      ),
      child: IntrinsicWidth(
        child: OnyxPanelSurface(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(OnyxMenuMetrics.padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (OnyxMenuMetrics.hairlineBefore(items, i))
                    const OnyxMenuHairline(),
                  OnyxMenuRow(
                    item: items[i],
                    height: widget.metrics.rowHeight(items[i]),
                    reserveCheck: choice,
                    focusNode: i == _initialIndex ? _initialFocus : null,
                    onSelect: () => widget.onPick(i),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnyxMenuHairline extends StatelessWidget {
  const OnyxMenuHairline({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(height: 1, color: AppColors.glassBorder),
      );
}

/// La ligne `_MenuRow` du menu du compte, généralisée (publique : les panneaux
/// d'[showAdaptivePanel] la réutilisent) : survol et focus la
/// remplissent de blanc à l'encre noire ; une ligne destructive reste rouge,
/// sur fond rouge pâle.
class OnyxMenuRow extends StatefulWidget {
  const OnyxMenuRow({
    super.key,
    required this.item,
    required this.height,
    required this.reserveCheck,
    required this.onSelect,
    this.focusNode,
  });

  final OnyxMenuItem<Object?> item;
  final double height;
  final bool reserveCheck;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  @override
  State<OnyxMenuRow> createState() => OnyxMenuRowState();
}

class OnyxMenuRowState extends State<OnyxMenuRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.enabled;
    final lit = enabled && (_focused || _hovered);
    final destructive = item.destructive;
    final Color background;
    final Color foreground;
    final Color secondary;
    if (!enabled) {
      background = Colors.transparent;
      foreground = AppColors.textMuted;
      secondary = AppColors.textMuted;
    } else if (destructive) {
      background =
          lit ? AppColors.error.withValues(alpha: 0.16) : Colors.transparent;
      foreground = AppColors.error;
      secondary = AppColors.error;
    } else {
      background = lit ? AppColors.textPrimary : Colors.transparent;
      foreground = lit ? AppColors.background : AppColors.textPrimary;
      secondary = lit ? AppColors.background : AppColors.textSecondary;
    }
    final select = enabled ? widget.onSelect : null;
    final subtitle = item.subtitle;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: item.checked,
      label: subtitle == null ? item.label : '${item.label}, $subtitle',
      excludeSemantics: true,
      child: TvFocusable(
        focusNode: widget.focusNode,
        enabled: enabled,
        focusScale: 1.0,
        showRing: false,
        borderRadius: BorderRadius.circular(10),
        onSelect: select,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: select,
            child: AnimatedContainer(
              duration: AppMotion.fade(context, AppMotion.micro),
              curve: AppMotion.curve,
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (item.leading != null) ...[
                    item.leading!,
                    const SizedBox(width: 12),
                  ] else if (item.icon != null) ...[
                    Icon(item.icon, size: 18, color: secondary),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: AppType.body,
                            fontWeight: item.checked
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondary,
                              fontSize: AppType.footnote,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // La place de la coche est réservée sur chaque ligne d'un
                  // menu de choix : les libellés restent alignés.
                  if (widget.reserveCheck) ...[
                    const SizedBox(width: 16),
                    Icon(
                      AppIcons.check,
                      size: 16,
                      color: item.checked ? foreground : Colors.transparent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
