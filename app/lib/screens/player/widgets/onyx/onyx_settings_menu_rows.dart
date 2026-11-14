part of 'onyx_settings_menu.dart';

// --- Rows ------------------------------------------------------------------

/// What makes a row reachable by a remote, and — the whole point — visible.
///
/// These rows used to be [InkWell]s. A remote could already walk them: the
/// arrows moved the focus exactly as they should. What it could not do is
/// *show* it. An ink highlight is painted by the enclosing [Material], which
/// here sits above the panel's own opaque background — so every ring, splash
/// and hover tint landed underneath it and never reached the screen. A menu
/// where nothing lights up is a menu a remote cannot be driven through, and it
/// reads from the sofa as an app that has stopped answering.
///
/// So the focus is drawn here instead, over the row. Sur un téléviseur, c'est
/// la pastille blanche à l'encre noire de toute commande focalisée
/// ([FocusFill], ADR-0112), qui dépasse un peu du rang comme dans les menus
/// de l'Apple TV (ADR-0130). The pointer gets its own, quieter tint — it had
/// lost its hover state to the same burial.
class _OnyxMenuTile extends StatefulWidget {
  /// La ligne, avec [lit] vrai quand elle est la pastille blanche : son
  /// contenu passe alors à l'encre.
  final Widget Function(BuildContext context, bool lit) builder;
  final VoidCallback onTap;
  final double minHeight;

  /// Supplied for the one row the remote is sent to on arrival.
  final FocusNode? focusNode;

  const _OnyxMenuTile({
    required this.builder,
    required this.onTap,
    required this.minHeight,
    this.focusNode,
  });

  @override
  State<_OnyxMenuTile> createState() => _OnyxMenuTileState();
}

class _OnyxMenuTileState extends State<_OnyxMenuTile> {
  bool _hovered = false;

  /// Le nœud de la ligne quand le menu n'en fournit pas. L'éclairage se lit
  /// sur lui, pas sur le `Focus` le plus proche : sous dpad, `TvFocusable`
  /// pose sous la cible un `Focus` qui ne prend jamais le focus (son enfant
  /// en est exclu), et la ligne focalisée restait éteinte (ADR-0110,
  /// phase 7).
  FocusNode? _ownedNode;

  FocusNode get _node =>
      widget.focusNode ??
      (_ownedNode ??= FocusNode(debugLabel: 'onyx-menu-row'));

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    final tv = TvMode.isTv;
    final radius = BorderRadius.circular(style.rowRadius);
    return TvFocusable(
      focusNode: _node,
      onSelect: widget.onTap,
      borderRadius: radius,
      // La pastille dit le focus d'une télécommande ; un clavier garde l'anneau.
      showRing: !tv,
      // Rows touch each other: growing one would climb over its neighbour.
      focusScale: 1.0,
      // A long list — twelve chapters — reads better with the outlined row
      // near the top than pinned to the middle.
      scrollAlignment: 0.3,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          // Read from the node rather than kept in a flag of our own: the menu
          // hands one node from row to row as it changes section, so a row can
          // be built around a node that already holds the focus — and nothing
          // would ever announce a change that never happened.
          child: ListenableBuilder(
            listenable: _node,
            builder: (context, _) {
              final focused = _node.hasFocus;
              final lit = tv && focused;
              // La pastille gagne en largeur ce qu'elle rend en retrait : le
              // texte ne bouge pas quand le focus arrive.
              final margin = lit ? 0.0 : style.overhang;
              return AnimatedContainer(
                duration: AppMotion.move(context, AppMotion.focus),
                curve: AppMotion.curve,
                margin: EdgeInsets.symmetric(horizontal: margin, vertical: 1),
                padding: EdgeInsets.symmetric(
                  horizontal: style.rowInset + style.overhang - margin,
                ),
                constraints: BoxConstraints(minHeight: widget.minHeight),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: lit
                      ? FocusFill.fill
                      : focused
                          ? OnyxChromeTheme.glassControl
                          : _hovered
                              ? OnyxChromeTheme.glassCard
                              : Colors.transparent,
                  boxShadow: lit
                      ? const [
                          BoxShadow(
                            color: OnyxChromeTheme.glassShadow,
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: widget.builder(context, lit),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Index row: what the setting is on, without opening it.
class _OnyxMenuRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const _OnyxMenuRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    return _OnyxMenuTile(
      onTap: onTap,
      focusNode: focusNode,
      minHeight: style.rowHeight,
      builder: (context, lit) {
        final ink = lit ? FocusFill.ink : OnyxChromeTheme.title;
        final quiet = lit ? _quietInk : OnyxChromeTheme.meta;
        return Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: ink,
                fontSize: style.labelSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            // La valeur prend ce qui reste et se cale à droite : les chevrons
            // tombent sur une même verticale, quelle que soit sa longueur.
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: quiet, fontSize: style.valueSize),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: quiet),
          ],
        );
      },
    );
  }
}

/// L'encre discrète d'une ligne focalisée : sa seconde ligne, sa valeur.
final Color _quietInk = FocusFill.ink.withValues(alpha: 0.62);

/// Choice row: a check occupies the left slot whether or not it is set, so the
/// labels stay on one vertical line.
class _OnyxMenuOption extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String? value;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const _OnyxMenuOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.value,
    this.badge,
    this.focusNode,
  });

  /// The entry node is placed by the list, which is the only thing that knows
  /// which option is the current one — the sections build their rows without
  /// looking at each other.
  _OnyxMenuOption withFocusNode(FocusNode? node) => _OnyxMenuOption(
        label: label,
        selected: selected,
        onTap: onTap,
        subtitle: subtitle,
        value: value,
        badge: badge,
        focusNode: node,
      );

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    final hasDetail = subtitle != null && subtitle!.isNotEmpty;
    return _OnyxMenuTile(
      onTap: onTap,
      focusNode: focusNode,
      minHeight: hasDetail ? style.tallRowHeight : style.rowHeight,
      builder: (context, lit) {
        final ink = lit ? FocusFill.ink : OnyxChromeTheme.title;
        final quiet = lit ? _quietInk : OnyxChromeTheme.time;
        return Row(
          children: [
            SizedBox(
              width: style.checkSlot,
              child: selected
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.check_rounded,
                        size: style.checkSize,
                        color: ink,
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontSize: style.labelSize,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        _OnyxMenuBadge(text: badge!, color: quiet),
                      ],
                    ],
                  ),
                  if (hasDetail)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        // Deux lignes : la description d'un format d'image
                        // est plus longue que le panneau n'est large.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: quiet,
                          fontSize: style.detailSize,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(
                value!,
                style: TextStyle(
                  color: quiet,
                  fontSize: style.valueSize,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// L'en-tête du menu d'un seul réglage : son nom, rien à activer.
class _OnyxMenuHeader extends StatelessWidget {
  final String title;

  const _OnyxMenuHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    return Container(
      height: style.headerHeight,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        horizontal: style.padding + style.rowInset,
      ),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: OnyxChromeTheme.time,
          fontSize: style.headerSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// L'en-tête d'une section ouverte depuis l'index : il y ramène.
class _OnyxMenuBackHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _OnyxMenuBackHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: style.padding - style.overhang,
      ),
      child: _OnyxMenuTile(
        onTap: onBack,
        minHeight: style.rowHeight,
        builder: (context, lit) {
          final ink = lit ? FocusFill.ink : OnyxChromeTheme.title;
          return Row(
            children: [
              Icon(Icons.chevron_left_rounded, size: 22, color: ink),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: ink,
                  fontSize: style.labelSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Le filet entre deux groupes de choix.
class _OnyxMenuDivider extends StatelessWidget {
  const _OnyxMenuDivider();

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    return Container(
      height: 1,
      margin: EdgeInsets.symmetric(
        horizontal: style.overhang + style.rowInset,
        vertical: 6,
      ),
      color: OnyxChromeTheme.glassBorder,
    );
  }
}

class _OnyxMenuBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _OnyxMenuBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: AppType.micro),
      ),
    );
  }
}

class _OnyxMenuEmpty extends StatelessWidget {
  const _OnyxMenuEmpty();

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 16,
        horizontal: style.padding + style.rowInset,
      ),
      child: Text(
        tr('Aucune piste disponible'),
        style: TextStyle(
          color: OnyxChromeTheme.meta,
          fontSize: style.detailSize,
        ),
      ),
    );
  }
}
