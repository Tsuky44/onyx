import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_deferred_keyboard.dart';
import '../settings_search.dart';
import 'settings_ui.dart';

/// Le champ qui cherche un réglage. Celui qui l'héberge garde le
/// [controller] : il décide quoi afficher à la place de sa liste tant qu'il y a
/// du texte.
class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TvDeferredKeyboard(
      builder: (context, focusNode, canRequestFocus) => TextField(
        focusNode: focusNode,
        canRequestFocus: canRequestFocus,
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: tr('Rechercher un paramètre'),
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: tr('Effacer la recherche'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Les réglages trouvés pour [query], ou le constat qu'il n'y en a pas.
class SettingsSearchResults extends StatelessWidget {
  const SettingsSearchResults({
    super.key,
    required this.index,
    required this.query,
    required this.onSelect,
  });

  final List<SettingsSearchEntry> index;
  final String query;
  final ValueChanged<SettingsSearchEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final hits = searchSettings(index, query);
    if (hits.isEmpty) {
      return SettingsEmptyNote(
        tr('Aucun résultat pour « {0} »', [query.trim()]),
        icon: Icons.search_off_rounded,
      );
    }
    return SettingsGroup(
      children: [
        for (final hit in hits)
          SettingsTile(
            icon: hit.icon,
            title: hit.title,
            subtitle: hit.path,
            onTap: () => onSelect(hit),
          ),
      ],
    );
  }
}

/// Teinte des résultats dans la barre latérale, plus dense que la liste mobile.
class SettingsSearchSidebarResults extends StatelessWidget {
  const SettingsSearchSidebarResults({
    super.key,
    required this.index,
    required this.query,
    required this.onSelect,
  });

  final List<SettingsSearchEntry> index;
  final String query;
  final ValueChanged<SettingsSearchEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final hits = searchSettings(index, query);
    if (hits.isEmpty) {
      return SettingsEmptyNote(
        tr('Aucun résultat pour « {0} »', [query.trim()]),
        icon: Icons.search_off_rounded,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final hit in hits)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            focusColor: AppColors.primary.withValues(alpha: 0.16),
            onTap: () => onSelect(hit),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(hit.icon, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hit.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: AppType.body)),
                        Text(hit.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: AppType.footnote)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
