import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_icons.dart';
import 'detail_hero.dart';
import 'onyx_menu.dart';

/// Le bouton « Plus » d'une fiche hors TV (ADR-0132) : une pastille nommée
/// qui ouvre, collé à elle, le menu Onyx des actions moins fréquentes.
///
/// Les lignes portent leur geste en valeur : le menu se referme puis le
/// lance. [anchorKey] laisse l'appelant rouvrir un second menu au même
/// endroit (« Corriger la fiche… » d'une série, qui propose deux voies).
class DetailMoreButton extends StatefulWidget {
  const DetailMoreButton({super.key, required this.items, this.anchorKey});

  final List<OnyxMenuItem<VoidCallback>> items;
  final GlobalKey? anchorKey;

  @override
  State<DetailMoreButton> createState() => _DetailMoreButtonState();
}

class _DetailMoreButtonState extends State<DetailMoreButton> {
  final GlobalKey _ownKey = GlobalKey();

  GlobalKey get _anchor => widget.anchorKey ?? _ownKey;

  Future<void> _open() async {
    final pick = await showOnyxMenu<VoidCallback>(
      context: context,
      anchorKey: _anchor,
      items: widget.items,
    );
    if (pick != null && mounted) pick.value();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return KeyedSubtree(
      key: _anchor,
      child: HeroPill(
        label: tr('Plus'),
        icon: AppIcons.more,
        style: HeroPillStyle.status,
        onPressed: _open,
      ),
    );
  }
}
