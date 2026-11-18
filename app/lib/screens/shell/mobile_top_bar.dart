import 'dart:ui';

import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../widgets/global/account_menu.dart';
import '../../widgets/global/app_download_button.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../widgets/global/liquid_glass.dart';
import '../../widgets/global/onyx_mark.dart';
import '../../widgets/global/onyx_wordmark.dart';

/// La barre du haut du téléphone, la même sur chaque onglet (ADR-0144) : la
/// marque dans une pilule de verre liquide (elle ramène à l'accueil), le
/// compte dans un rond du même verre, la matière de la capsule du bas.
/// La recherche est en bas, dans le rond de la barre d'onglets (ADR-0142).
///
/// Pas de bandeau : l'affiche de l'accueil monte sous l'heure et sous la
/// barre, et les deux pièces de verre flottent dessus. Quand la page a quitté
/// son haut ([scrolled]), rien ne s'allume non plus : ce qui défile se floute
/// et s'assombrit en fondu sous elles ([ScrollEdgeBlur]), comme dans les apps
/// d'iOS 26.
class MobileTopBar extends StatelessWidget {
  final bool scrolled;
  final AuthProvider authProvider;
  final HomeProvider homeProvider;
  final VoidCallback onLogoTap;

  const MobileTopBar({
    super.key,
    required this.scrolled,
    required this.authProvider,
    required this.homeProvider,
    required this.onLogoTap,
  });

  /// La rangée des pièces de verre, sous la barre d'état.
  static const double rowHeight = 56;

  /// Jusqu'où le flou descend sous la rangée avant de s'éteindre.
  static const double fadeBelow = 36;

  @override
  Widget build(BuildContext context) {
    final working = homeProvider.isScanning ||
        homeProvider.isBackfillingMetadata ||
        homeProvider.isRedetectingAll ||
        homeProvider.isExtractingSubtitles;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: -fadeBelow,
          child: IgnorePointer(
            child: AnimatedOpacity(
              key: const ValueKey('mobile-top-bar-edge'),
              opacity: scrolled ? 1 : 0,
              duration: AppMotion.fade(context, AppMotion.emphasis),
              curve: AppMotion.curve,
              child: const ScrollEdgeBlur(),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  BrandPill(onTap: onLogoTap),
                  const Spacer(),
                  if (working)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  const AppDownloadButton(),
                  const SizedBox(width: 4),
                  AccountMenu(authProvider: authProvider, liquid: true),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La marque dans une pilule de verre liquide : la lentille et le nom
/// dessiné. La toucher ramène à l'accueil.
class BrandPill extends StatelessWidget {
  const BrandPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Accueil'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox(
          height: AccountMenu.liquidSize,
          child: LiquidGlass(
            child: Padding(
              padding: EdgeInsets.fromLTRB(9, 0, 16, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OnyxMark(size: 26),
                  SizedBox(width: 8),
                  OnyxWordmark(height: 12, shadow: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le bord du haut d'une page qui défile sous la barre du téléphone : flou et
/// assombri en haut, net et clair en bas, sans arête (ADR-0144).
///
/// Flutter ne sait pas dégrader un flou : cinq bandes de flou de plus en
/// plus léger, assez rapprochées pour que leurs marches ne se lisent pas, et
/// par-dessus un voile vers la couleur de la page, qui les fond. Sans flou
/// ([glassBlurs]), le voile seul, plus dense.
class ScrollEdgeBlur extends StatelessWidget {
  const ScrollEdgeBlur({super.key});

  /// Les bandes de flou, de haut en bas : (début, fin) en fraction de la
  /// hauteur, et la force du flou.
  static const List<(double, double, double)> bands = [
    (0, 0.45, 16),
    (0.45, 0.62, 10),
    (0.62, 0.76, 6),
    (0.76, 0.88, 3),
    (0.88, 0.96, 1.2),
  ];

  @override
  Widget build(BuildContext context) {
    final blurs = glassBlurs(context);
    final veil = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: blurs ? 0.92 : 0.96),
            AppColors.background.withValues(alpha: blurs ? 0.78 : 0.86),
            AppColors.background.withValues(alpha: blurs ? 0.4 : 0.5),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 0.75, 1],
        ),
      ),
    );
    if (!blurs) return veil;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final (start, end, sigma) in bands)
              Positioned(
                top: start * height,
                height: (end - start) * height,
                left: 0,
                right: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            veil,
          ],
        );
      },
    );
  }
}

/// Signale quand la liste verticale principale de [child] quitte son haut, ou
/// y revient.
///
/// Ne lit que la profondeur 0 : les rangées horizontales et les listes
/// imbriquées défilent sans que la page, elle, ait bougé.
class ScrollEdgeListener extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool> onScrolledChanged;

  const ScrollEdgeListener({
    super.key,
    required this.child,
    required this.onScrolledChanged,
  });

  /// Au-delà de quelques pixels seulement : un rebond iOS en haut de page ne
  /// doit pas faire clignoter le verre.
  static const double threshold = 8;

  @override
  State<ScrollEdgeListener> createState() => _ScrollEdgeListenerState();
}

class _ScrollEdgeListenerState extends State<ScrollEdgeListener> {
  bool _scrolled = false;

  bool _onNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final scrolled = notification.metrics.pixels > ScrollEdgeListener.threshold;
    if (scrolled != _scrolled) {
      _scrolled = scrolled;
      widget.onScrolledChanged(scrolled);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.child,
    );
  }
}
