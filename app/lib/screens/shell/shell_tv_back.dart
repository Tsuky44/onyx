import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/tr.dart';
import '../../tv/nav/onyx_dpad.dart' show TvNavScope;
import '../../tv/nav/tv_back.dart';
import '../../tv/tv_deferred_keyboard.dart';

/// Le Retour d'une télécommande sur l'écran principal, selon le système de
/// navigation monté (ADR-0110).
///
/// - **dpad** : une marche de [TvBack] (règle 3). Depuis le contenu d'un
///   onglet, Retour remonte à l'onglet affiché dans l'en-tête ; depuis
///   l'en-tête, quel que soit l'onglet, il est rendu au système, qui ramène à
///   l'écran d'accueil de l'appareil. Pas de retour à l'accueil d'abord, pas
///   de « appuyez de nouveau » : c'est retenir Menu à la racine, ce que
///   l'App Review tvOS refuse (ADR-0110, phase 5).
/// - **legacy** : le `PopScope` d'avant la refonte, à l'identique. Il remonte
///   d'un cran à la fois, comme sur Android TV : du contenu vers l'onglet
///   affiché, d'un autre onglet vers l'accueil, et de l'accueil vers la
///   sortie — après confirmation, parce qu'un appui de trop en remontant ne
///   doit pas fermer l'app. Il part avec le drapeau `ONYX_TV_NAV`.
///
/// Ne se pose que sur un téléviseur.
class ShellTvBack extends StatefulWidget {
  const ShellTvBack({
    super.key,
    required this.headerNode,
    required this.selectedTab,
    required this.homeTab,
    required this.focusTab,
    required this.selectTab,
    required this.child,
  });

  /// L'en-tête entier, qui ne prend jamais le focus lui-même : il dit si la
  /// télécommande y est.
  final FocusNode headerNode;

  /// L'onglet affiché, et celui de l'accueil.
  final String selectedTab;
  final String homeTab;

  /// Pose la télécommande sur un onglet de l'en-tête.
  final ValueChanged<String> focusTab;

  /// Affiche un onglet (ancien système seulement : sous dpad, Retour ne
  /// change pas d'onglet).
  final ValueChanged<String> selectTab;

  final Widget child;

  @override
  State<ShellTvBack> createState() => _ShellTvBackState();
}

class _ShellTvBackState extends State<ShellTvBack> {
  /// Le moment où Retour a été pressé une première fois sur l'accueil. Un
  /// second appui dans [_exitWindow] quitte l'app (ancien système).
  DateTime? _exitArmedAt;
  static const Duration _exitWindow = Duration(seconds: 3);

  /// La marche de [TvBack] : vrai quand l'appui a remonté le focus.
  bool _backToHeader() {
    if (widget.headerNode.hasFocus) return false;
    widget.focusTab(widget.selectedTab);
    return true;
  }

  void _handleLegacyBack() {
    // Le champ de recherche gardait le focus clavier fermé : Retour proposait
    // de quitter l'app au lieu de rendre la télécommande à la barre.
    if (TvDeferredKeyboardState.releaseFocused()) return;
    if (!widget.headerNode.hasFocus) {
      widget.focusTab(widget.selectedTab);
      return;
    }
    if (widget.selectedTab != widget.homeTab) {
      widget.selectTab(widget.homeTab);
      widget.focusTab(widget.homeTab);
      return;
    }
    final now = DateTime.now();
    final armed = _exitArmedAt;
    if (armed != null && now.difference(armed) < _exitWindow) {
      SystemNavigator.pop();
      return;
    }
    _exitArmedAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Appuyez de nouveau sur Retour pour quitter')),
        duration: _exitWindow,
      ));
  }

  @override
  Widget build(BuildContext context) {
    if (TvNavScope.isActive(context)) {
      return TvBackStep(onBack: _backToHeader, child: widget.child);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleLegacyBack();
      },
      child: widget.child,
    );
  }
}
