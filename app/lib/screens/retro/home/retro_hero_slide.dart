import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_type.dart';
import '../../../theme/retro_palette.dart';
import '../../../tv/tv_mode.dart';
import '../../../widgets/global/hero/hero_actions.dart';
import '../../../widgets/global/liquid_glass.dart';
import '../widgets/retro_ambient.dart';
import 'retro_home_text.dart';
import 'retro_poster_fan.dart';

/// La première diapo du carrousel de l'accueil tant que le Rétro n'a pas été
/// ouvert (ADR 2026-11-26-tsuky-retro-annuel) : le prénom, les heures et les
/// affiches de l'année, aux couleurs du profil. « Voir mon Rétro » l'ouvre ;
/// « Plus tard » la range pour la session.
///
/// Le texte se pose comme celui d'un bandeau ordinaire (`HeroBanner`), aux
/// mêmes marges, pour que les traits du carrousel et la rangée qui suit ne
/// bougent pas d'une diapo à l'autre.
class RetroHeroSlide extends StatelessWidget {
  const RetroHeroSlide({
    super.key,
    required this.status,
    required this.report,
    required this.name,
    required this.serverBaseUrl,
    required this.onOpen,
    required this.onLater,
    this.extendTop = 0,
    this.autofocus = false,
  });

  final RetroStatus status;

  /// Le Rétro, quand il est déjà chargé : sans lui, la diapo dit l'essentiel
  /// sans chiffres ni affiches.
  final RetroReport? report;
  final String name;
  final String? serverBaseUrl;
  final VoidCallback onOpen;
  final VoidCallback onLater;

  /// Voir `HeroBanner.extendTop`.
  final double extendTop;

  /// Le bouton prend le focus d'office : sur un téléviseur, c'est là que la
  /// télécommande commence.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isTv = TvScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 600;
    final report = this.report;
    final palette =
        RetroPalette.forArchetype(report?.archetype ?? RetroArchetype.marathon);
    final horizontal = isCompact ? 16.0 : 48.0;
    final textBottom = isCompact
        ? 52.0
        : isTv
            ? 72.0
            : 140.0;
    final title = tr('{0}, ton année est prête.', [name]);
    final teaser = RetroHomeText.teaser(report);

    final open = HeroPlayButton(
      label: tr('Voir mon Rétro'),
      onPressed: onOpen,
      autofocus: autofocus,
      isTv: isTv,
    );
    final later = _LaterButton(onPressed: onLater, isTv: isTv);

    return Semantics(
      container: true,
      label: '$title $teaser',
      child: LayoutBuilder(builder: (context, constraints) {
        final height = constraints.maxHeight;
        final room = height - extendTop;
        final fanHeight = room * (isCompact ? 0.5 : 0.62);
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: palette.background),
            RetroAmbientLayer(
              ambient: RetroOrbs(RetroPalette.glowsFor(palette)),
              ink: palette.ink,
            ),
            if (report != null && report.top.isNotEmpty)
              Positioned(
                right: isCompact ? -width * 0.06 : horizontal + 24,
                top: extendTop + room * (isCompact ? 0.04 : 0.12),
                height: fanHeight,
                child: Opacity(
                  // Sur un téléphone, le texte passe devant les affiches.
                  opacity: isCompact ? 0.55 : 1,
                  child: FittedBox(
                    child: RetroPosterFan(
                      titles: report.top,
                      serverBaseUrl: serverBaseUrl,
                      posterWidth: 120,
                    ),
                  ),
                ),
              ),
            // Les mêmes voiles qu'un bandeau : vers la couleur du profil à
            // gauche, sous le texte ; vers la page en bas, pour que la rangée
            // qui suit continue la diapo.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    palette.background.withValues(alpha: isCompact ? 0.5 : 0.9),
                    palette.background.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.6],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0),
                    AppColors.background.withValues(alpha: 0),
                    AppColors.background,
                  ],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
            Positioned(
              left: horizontal,
              right: horizontal,
              bottom: textBottom,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: isCompact ? double.infinity : 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        RetroHomeText.kicker(status).toUpperCase(),
                        style: TextStyle(
                          color: palette.ink.withValues(alpha: 0.85),
                          fontSize: AppType.footnote,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: palette.ink,
                          fontSize:
                              isCompact ? AppType.largeTitle : AppType.hero,
                          fontWeight: FontWeight.w800,
                          height: 1.02,
                          letterSpacing: isCompact ? -0.8 : -1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        teaser,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.ink.withValues(alpha: 0.85),
                          fontSize: AppType.callout,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: isCompact ? 20 : 24),
                      if (isCompact)
                        Row(
                          children: [
                            Expanded(child: open),
                            const SizedBox(width: 10),
                            later,
                          ],
                        )
                      else
                        Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [open, later]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// « Plus tard » : le pendant de « Plus d'infos » d'un bandeau, en verre hors
/// téléviseur.
class _LaterButton extends StatelessWidget {
  const _LaterButton({required this.onPressed, required this.isTv});
  final VoidCallback onPressed;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final label = Text(tr('Plus tard'));
    if (isTv) {
      return OutlinedButton(
        onPressed: onPressed,
        style: AppTheme.focusRinged(
          OutlinedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          resting: BorderSide.none,
        ),
        child: label,
      );
    }
    return LiquidGlass(
      child: OutlinedButton(
        onPressed: onPressed,
        style: AppTheme.focusRinged(
          OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: AppColors.textPrimary,
            shape: const StadiumBorder(),
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
          resting: BorderSide.none,
        ),
        child: label,
      ),
    );
  }
}
