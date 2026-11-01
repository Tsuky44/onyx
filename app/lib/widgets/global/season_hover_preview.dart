import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import 'app_network_image.dart';

/// Ce que la fiche d'une saison montre, quelle que soit sa source : une saison
/// de la bibliothèque (`Media`) ou une saison de TMDB sur la fiche d'une
/// demande. Chaque écran la remplit, la fiche ne connaît aucun modèle.
class SeasonPreviewInfo {
  final String title;

  /// Année, nombre d'épisodes, état : déjà assemblés, dans l'ordre d'affichage.
  final List<String> facts;
  final String overview;

  /// Déjà résolue (affiche de repli, serveur) : la fiche l'affiche telle quelle.
  final String? posterUrl;

  const SeasonPreviewInfo({
    required this.title,
    required this.facts,
    required this.overview,
    required this.posterUrl,
  });
}

/// Laisser la souris sur l'onglet d'une saison ouvre sa fiche juste dessous :
/// affiche, année, nombre d'épisodes, résumé. Un clic sur la fiche en ouvre la
/// page ([onOpen], dit par [openLabel]) ; un clic sur l'onglet, lui, change
/// toujours de saison.
///
/// Seule une souris survole : au toucher et à la télécommande, rien ne
/// s'ouvre, l'onglet garde son geste.
class SeasonHoverPreview extends StatefulWidget {
  final SeasonPreviewInfo info;
  final String openLabel;
  final VoidCallback onOpen;
  final Widget child;

  const SeasonHoverPreview({
    super.key,
    required this.info,
    required this.openLabel,
    required this.onOpen,
    required this.child,
  });

  /// Le temps de laisser le curseur traverser la rangée sans ouvrir une fiche
  /// par onglet croisé.
  static const Duration openDelay = Duration(milliseconds: 400);

  /// Le temps de passer de l'onglet à la fiche, huit pixels plus bas.
  static const Duration closeDelay = Duration(milliseconds: 150);

  @override
  State<SeasonHoverPreview> createState() => _SeasonHoverPreviewState();
}

class _SeasonHoverPreviewState extends State<SeasonHoverPreview> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  Timer? _openTimer;
  Timer? _closeTimer;

  void _enter() {
    _closeTimer?.cancel();
    if (_portal.isShowing) return;
    _openTimer?.cancel();
    _openTimer = Timer(SeasonHoverPreview.openDelay, _portal.show);
  }

  void _leave() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _closeTimer = Timer(SeasonHoverPreview.closeDelay, _portal.hide);
  }

  void _open() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _portal.hide();
    widget.onOpen();
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  /// Décalage vers la gauche quand la fiche déborderait de la fenêtre : les
  /// derniers onglets d'une longue série sont près du bord droit.
  double _horizontalShift(double screenWidth) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    final left = box.localToGlobal(Offset.zero).dx;
    final overflow = left + SeasonPreviewCard.width + 16 - screenWidth;
    return overflow > 0 ? -overflow : 0;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        final shift = _horizontalShift(MediaQuery.sizeOf(overlayContext).width);
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            offset: Offset(shift, 8),
            child: MouseRegion(
              onEnter: (_) => _enter(),
              onExit: (_) => _leave(),
              child: _Appear(
                child: SeasonPreviewCard(
                  info: widget.info,
                  openLabel: widget.openLabel,
                  onOpen: _open,
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _leave(),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fondu et léger glissement vers le bas, coupés quand le système demande
/// moins d'animations ([AppMotion.fade]).
class _Appear extends StatelessWidget {
  final Widget child;

  const _Appear({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.fade(context, AppMotion.micro),
      curve: AppMotion.curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * -6), child: child),
      ),
      child: child,
    );
  }
}

/// La fiche d'une saison au survol de son onglet.
class SeasonPreviewCard extends StatefulWidget {
  final SeasonPreviewInfo info;
  final String openLabel;
  final VoidCallback onOpen;

  const SeasonPreviewCard({
    super.key,
    required this.info,
    required this.openLabel,
    required this.onOpen,
  });

  static const double width = 380;
  static const double _posterWidth = 100;

  @override
  State<SeasonPreviewCard> createState() => _SeasonPreviewCardState();
}

class _SeasonPreviewCardState extends State<SeasonPreviewCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final overview = info.overview.trim();
    final facts = info.facts;
    final radius = BorderRadius.circular(12);

    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          child: AnimatedContainer(
            duration: AppMotion.fade(context, AppMotion.micro),
            curve: AppMotion.curve,
            width: SeasonPreviewCard.width,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  _hovered ? AppColors.surfaceHover : AppColors.surfaceElevated,
              borderRadius: radius,
              border: Border.all(
                color: _hovered
                    ? AppColors.textSecondary.withValues(alpha: 0.5)
                    : AppColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AppNetworkImage(
                    url: info.posterUrl,
                    width: SeasonPreviewCard._posterWidth,
                    height: SeasonPreviewCard._posterWidth * 3 / 2,
                    fit: BoxFit.cover,
                    placeholder: const ColoredBox(color: AppColors.surface),
                    errorWidget: const ColoredBox(
                      color: AppColors.surface,
                      child: Icon(AppIcons.movie, color: AppColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: AppType.headline,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          facts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: AppType.footnote,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        overview.isNotEmpty
                            ? overview
                            : tr('Pas de résumé pour cette saison.'),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: overview.isNotEmpty
                              ? AppColors.textSecondary
                              : AppColors.textMuted,
                          fontSize: AppType.subhead,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            widget.openLabel,
                            style: TextStyle(
                              color: _hovered
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: AppType.footnote,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            AppIcons.chevronRight,
                            size: 12,
                            color: _hovered
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
