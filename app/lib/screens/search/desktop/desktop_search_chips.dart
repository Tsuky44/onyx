import 'package:flutter/material.dart';

import '../search_chips.dart';
import '../search_layout.dart';
import 'desktop_search_controller.dart';

/// Les pastilles au-dessus des résultats du bureau ([SearchFilterChips]),
/// branchées sur la pastille du contrôleur.
///
/// Elles ne prennent jamais le focus : on les clique, et le champ de
/// l'en-tête garde la frappe.
class DesktopSearchChips extends StatelessWidget {
  const DesktopSearchChips({
    super.key,
    required this.controller,
    required this.layout,
    required this.showUnavailable,
  });

  final DesktopSearchController controller;
  final SearchLayout layout;

  /// Voir [SearchFilterChips.showUnavailable].
  final bool showUnavailable;

  @override
  Widget build(BuildContext context) {
    return SearchFilterChips(
      layout: layout,
      selected: controller.filter.value,
      onSelected: controller.setFilter,
      showUnavailable: showUnavailable,
    );
  }
}
