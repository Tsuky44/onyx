import 'package:flutter/material.dart';

import '../../../../theme/app_type.dart';
import '../../hooks/use_player_stats.dart';
import '../onyx/onyx_chrome_theme.dart';

/// L'onglet « Stats » du lecteur : ce que le moteur fait vraiment, relu chaque
/// seconde tant que l'onglet est à l'écran (ADR-0130).
///
/// Rien à activer : douze mesures, rangées en colonnes. Le relevé démarre
/// avec l'onglet et s'arrête avec lui ([PlayerLiveStats.watch]).
class PlayerStatsTab extends StatefulWidget {
  const PlayerStatsTab({super.key, required this.stats});

  final PlayerLiveStats stats;

  @override
  State<PlayerStatsTab> createState() => _PlayerStatsTabState();
}

class _PlayerStatsTabState extends State<PlayerStatsTab> {
  @override
  void initState() {
    super.initState();
    widget.stats.watch();
  }

  @override
  void didUpdateWidget(PlayerStatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.stats, widget.stats)) return;
    oldWidget.stats.unwatch();
    widget.stats.watch();
  }

  @override
  void dispose() {
    widget.stats.unwatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Quatre colonnes sur un téléviseur ou un bureau, moins quand la
        // place manque : une mesure garde au moins 180 de large.
        final columns = (constraints.maxWidth / 180).floor().clamp(1, 4);
        const gap = 24.0;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return ListenableBuilder(
          listenable: widget.stats,
          builder: (context, _) => SingleChildScrollView(
            child: Wrap(
              spacing: gap,
              runSpacing: 18,
              children: [
                for (final line in widget.stats.lines)
                  SizedBox(
                    width: cell,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          line.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: OnyxChromeTheme.meta,
                            fontSize: AppType.subhead,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          line.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: OnyxChromeTheme.title,
                            fontSize: AppType.headline,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
