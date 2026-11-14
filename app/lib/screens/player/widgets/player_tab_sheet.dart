import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_motion.dart';
import 'onyx/onyx_chrome_theme.dart';
import 'onyx/onyx_glass_panel.dart';
import 'onyx/onyx_tabs.dart';

/// Les onglets du lecteur sur un écran à souris ou à doigt : une feuille de
/// verre qui monte du bas, ses onglets en tête (ADR-0130).
///
/// Les mêmes onglets et les mêmes contenus que le volet d'un téléviseur
/// (`OnyxTvTabs`), ouverts d'un bouton de la barre au lieu d'un pas de
/// télécommande. Un tap à côté la ferme. Elle remplace le panneau des
/// épisodes et la fenêtre « Regarder ensemble », qui étaient deux panneaux
/// pour deux boutons.
class PlayerTabSheet extends StatelessWidget {
  const PlayerTabSheet({
    super.key,
    required this.tabs,
    required this.open,
    required this.onChanged,
  });

  final List<OnyxTabEntry> tabs;
  final OnyxTab open;

  /// Un autre onglet, ou `null` pour fermer la feuille.
  final ValueChanged<OnyxTab?> onChanged;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Un peu plus de la moitié de l'écran, bornée : sur un téléphone tenu en
    // largeur il faut au moins la place d'une rangée de cartes, sur un grand
    // moniteur la feuille ne doit pas manger le film.
    final height = (size.height * 0.52).clamp(280.0, 420.0);
    final entry =
        tabs.where((tab) => tab.tab == open).firstOrNull ?? tabs.firstOrNull;

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => onChanged(null),
            child: const ColoredBox(
              color: OnyxChromeTheme.questionVeil,
              child: SizedBox.expand(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: OnyxGlassPanel(
              radius: const BorderRadius.vertical(top: Radius.circular(20)),
              outlined: false,
              elevated: false,
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  height: height,
                  width: double.infinity,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final tab in tabs)
                                        OnyxChromeTab(
                                          key: ValueKey(
                                              'onyx-tab-${tab.tab.name}'),
                                          label: tab.label,
                                          active: tab.marked,
                                          selected: tab.tab == entry?.tab,
                                          onPressed: () => onChanged(tab.tab),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: tr('Fermer'),
                                onPressed: () => onChanged(null),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: OnyxChromeTheme.icon,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (entry != null)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 14, 24, 16),
                              child: KeyedSubtree(
                                key: ValueKey(entry.tab),
                                child: entry.builder(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ).animate().slideY(
                begin: 0.12,
                end: 0,
                duration: AppMotion.move(context, AppMotion.emphasis),
                curve: Curves.easeOutCubic,
              ),
        ],
      ),
    );
  }
}
