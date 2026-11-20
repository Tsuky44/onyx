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
import '../../widgets/global/onyx_mark.dart';
import '../../widgets/global/onyx_wordmark.dart';

/// La barre du haut du téléphone, la même sur chaque onglet (ADR-0144) : la
/// marque (elle ramène à l'accueil) et le compte, posés sans verre sur le noir
/// de la page, comme l'app Apple TV. La recherche est en bas, dans le rond de
/// la barre d'onglets (ADR-0142).
///
/// Pas de bandeau : sur l'accueil, l'affiche se fond dans ce noir juste sous
/// eux. Quand la page a quitté son haut ([scrolled]), rien ne s'allume non
/// plus : ce qui défile se floute et s'assombrit en fondu sous eux
/// ([ScrollEdgeBlur]), comme dans les apps d'iOS 26.
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

  /// La rangée de la marque et du compte, sous la barre d'état.
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
                  AccountMenu(authProvider: authProvider, plain: true),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La marque : la lentille et le nom dessiné, en blanc, avec une ombre douce
/// qui les garde lisibles sur une affiche claire. Sans verre : posée sur le
/// noir, une pilule transparente laissait voir l'affiche à travers le logo.
/// La toucher ramène à l'accueil.
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
        child: SizedBox(
          height: AccountMenu.plainTarget,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const OnyxMark(size: 26),
              ),
              const SizedBox(width: 8),
              const OnyxWordmark(height: 12, shadow: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le bord du haut d'une page qui défile sous la barre du téléphone : flou et
/// assombri en haut, net et clair en bas, sans marche ni arête (ADR-0144).
///
/// Sous Impeller, un flou dont la force baisse en continu de haut en bas
/// (`shaders/scroll_edge_blur.frag`, deux passes). Ailleurs, des bandes de
/// flou de plus en plus léger : leurs marches se voyaient sur de vraies
/// affiches, d'où le shader. Par-dessus, un voile vers la couleur de la page,
/// en courbe : en trois droites, ses coudes se lisaient en lignes. Sans flou
/// ([glassBlurs]), le voile seul, plus dense.
class ScrollEdgeBlur extends StatefulWidget {
  const ScrollEdgeBlur({super.key});

  /// Le flou le plus fort, en haut (écart type, en points).
  static const double sigma = 14;

  /// Le repli hors Impeller : (début, fin) en fraction de la hauteur, et la
  /// force du flou.
  static const List<(double, double, double)> bands = [
    (0, 0.45, 16),
    (0.45, 0.62, 10),
    (0.62, 0.76, 6),
    (0.76, 0.88, 3),
    (0.88, 0.96, 1.2),
  ];

  /// La densité du voile à la hauteur [t] (0 en haut, 1 en bas) : forte sous
  /// l'heure, elle s'éteint en bas sans pente, donc sans ligne.
  static double veilAt(double t, {required bool blurs}) {
    final top = blurs ? 0.92 : 0.96;
    final fall = 1 - t * t * t;
    return top * fall * fall;
  }

  static const int _veilStops = 13;

  @override
  State<ScrollEdgeBlur> createState() => _ScrollEdgeBlurState();
}

class _ScrollEdgeBlurState extends State<ScrollEdgeBlur> {
  static FragmentProgram? _program;
  static Future<void>? _loading;

  FragmentShader? _horizontal;
  FragmentShader? _vertical;

  @override
  void initState() {
    super.initState();
    if (!ImageFilter.isShaderFilterSupported) return;
    if (_program != null) {
      _makeShaders();
      return;
    }
    _loading ??= FragmentProgram.fromAsset('shaders/scroll_edge_blur.frag')
        .then<void>((program) => _program = program)
        .catchError((Object error) {
      debugPrint('ScrollEdgeBlur: shader indisponible ($error)');
    });
    _loading!.then((_) {
      if (mounted && _program != null) setState(_makeShaders);
    });
  }

  void _makeShaders() {
    _horizontal = _program!.fragmentShader();
    _vertical = _program!.fragmentShader();
  }

  @override
  void dispose() {
    _horizontal?.dispose();
    _vertical?.dispose();
    super.dispose();
  }

  /// Le flou progressif, en deux passes, ou null tant que le shader n'est pas
  /// là (ou hors Impeller).
  ImageFilter? _progressive(double height) {
    final horizontal = _horizontal;
    final vertical = _vertical;
    if (horizontal == null || vertical == null) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final (shader, x, y) in [
      (horizontal, 1.0, 0.0),
      (vertical, 0.0, 1.0)
    ]) {
      // 0 et 1 : la taille de la texture, posée par le moteur.
      shader
        ..setFloat(2, height * dpr)
        ..setFloat(3, ScrollEdgeBlur.sigma * dpr)
        ..setFloat(4, x)
        ..setFloat(5, y);
    }
    return ImageFilter.compose(
      outer: ImageFilter.shader(vertical),
      inner: ImageFilter.shader(horizontal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blurs = glassBlurs(context);
    const last = ScrollEdgeBlur._veilStops - 1;
    final veil = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            for (var i = 0; i <= last; i++)
              AppColors.background.withValues(
                alpha: ScrollEdgeBlur.veilAt(i / last, blurs: blurs),
              ),
          ],
          stops: [for (var i = 0; i <= last; i++) i / last],
        ),
      ),
    );
    if (!blurs) return veil;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final progressive = _progressive(height);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (progressive != null)
              ClipRect(
                key: const ValueKey('scroll-edge-progressive'),
                child: BackdropFilter(
                  filter: progressive,
                  child: const SizedBox.expand(),
                ),
              )
            else
              for (final (start, end, sigma) in ScrollEdgeBlur.bands)
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
