import 'dart:async';

import 'package:flutter/material.dart';

import '../../desktop_window.dart' show tvShellHeaderBarHeight;
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../theme/focus_fill.dart';
import '../../tv/nav/onyx_dpad.dart' show TvNavScope;
import '../../tv/nav/tv_focusable.dart';
import 'glass_chrome.dart';

/// La barre d'onglets d'un téléviseur : une pilule de verre qui flotte, les
/// onglets en texte dedans (ADR-0117).
///
/// C'est la barre des apps de salon (tvOS, et l'en-tête d'Emby que
/// l'utilisateur a donné en modèle) : on la lit de loin parce qu'elle n'a que
/// trois états, portés par la capsule de l'onglet et non par un trait de 2 px.
///
/// - au repos, le texte seul, atténué ;
/// - **affiché**, une capsule de verre clair : on sait où l'on est même quand
///   la télécommande est dans la page ;
/// - **focalisé**, la capsule se remplit de blanc et le texte passe au noir,
///   comme toute commande sur téléviseur ([FocusFill], ADR-0112).
///
/// S'arrêter sur un onglet l'affiche, sans appuyer sur OK : c'est le geste des
/// barres d'onglets de tvOS ([TvTabBarItem.selectDelay]).
///
/// Les onglets en trop défilent dans la pilule : le nombre de bibliothèques
/// d'un serveur n'est pas borné.
class TvTabBar extends StatelessWidget {
  const TvTabBar({super.key, required this.children});

  /// Des [TvTabBarItem], et ce qui les enveloppe (ancres de la visite guidée).
  final List<Widget> children;

  /// La hauteur de la pilule, en pixels de la page TV (1280 de large).
  static const double height = tvShellHeaderBarHeight;

  static const double _inset = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: GlassSurface(
        borderRadius: const BorderRadius.all(Radius.circular(height / 2)),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(height / 2)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(_inset),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// Un onglet de [TvTabBar].
class TvTabBarItem extends StatefulWidget {
  const TvTabBarItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.focusNode,
  });

  final String label;

  /// Vrai pour l'onglet dont la page est affichée.
  final bool selected;
  final VoidCallback onTap;

  /// Fourni par la coquille, pour que Retour ramène la télécommande sur
  /// l'onglet affiché.
  final FocusNode? focusNode;

  /// Le temps que le focus doit rester sur un onglet pour l'afficher. Assez
  /// court pour sembler immédiat, assez long pour que traverser la barre d'un
  /// glissé ne monte pas chaque onglet survolé (une page montée charge son
  /// catalogue).
  static const Duration selectDelay = Duration(milliseconds: 220);

  @override
  State<TvTabBarItem> createState() => _TvTabBarItemState();
}

class _TvTabBarItemState extends State<TvTabBarItem> {
  bool _focused = false;
  Timer? _selectTimer;

  void _handleFocusChange(bool focused) {
    if (_focused == focused) return;
    setState(() => _focused = focused);
    _selectTimer?.cancel();
    _selectTimer = null;
    if (focused && !widget.selected) {
      _selectTimer = Timer(TvTabBarItem.selectDelay, () {
        if (mounted && _focused && !widget.selected) widget.onTap();
      });
    }
  }

  /// OK n'attend pas le délai, et ne le laisse pas choisir une seconde fois.
  void _select() {
    _selectTimer?.cancel();
    _selectTimer = null;
    widget.onTap();
  }

  @override
  void dispose() {
    _selectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sous dpad, c'est dpad qui tient le focus de l'onglet, pour en faire
    // l'entrée de l'en-tête quand il est affiché (ADR-0110) ; l'onglet
    // dessine toujours son propre focus.
    final dpad = TvNavScope.isActive(context);
    final tab = _buildTab(context, ownsFocus: !dpad);
    if (!dpad) return tab;
    return TvFocusable(
      focusNode: widget.focusNode,
      entry: widget.selected,
      onSelect: _select,
      onFocusChange: _handleFocusChange,
      showRing: false,
      focusScale: 1.0,
      child: tab,
    );
  }

  Widget _buildTab(BuildContext context, {required bool ownsFocus}) {
    final selected = widget.selected;
    const radius = BorderRadius.all(
      Radius.circular((TvTabBar.height - 2 * TvTabBar._inset) / 2),
    );
    final Color fill;
    final Color ink;
    if (_focused) {
      fill = FocusFill.fill;
      ink = FocusFill.ink;
    } else if (selected) {
      fill = Colors.white.withValues(alpha: 0.16);
      ink = AppColors.textPrimary;
    } else {
      fill = Colors.transparent;
      ink = AppColors.textSecondary;
    }

    return AnimatedScale(
      scale: _focused ? 1.04 : 1.0,
      duration: AppMotion.move(context, AppMotion.micro),
      curve: AppMotion.curve,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _select,
          focusNode: ownsFocus ? widget.focusNode : null,
          canRequestFocus: ownsFocus,
          onFocusChange: ownsFocus ? _handleFocusChange : null,
          // La capsule dit déjà tout : le voile de Material la grisait.
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: AppMotion.fade(context, AppMotion.micro),
            curve: AppMotion.curve,
            height: TvTabBar.height - 2 * TvTabBar._inset,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              boxShadow: _focused
                  ? const [
                      BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: AnimatedDefaultTextStyle(
              duration: AppMotion.fade(context, AppMotion.micro),
              curve: AppMotion.curve,
              // Fusionné et non remplacé : le style par défaut porte la
              // police de l'app.
              style: DefaultTextStyle.of(context).style.merge(TextStyle(
                    color: ink,
                    fontSize: AppType.callout,
                    fontWeight: selected || _focused
                        ? FontWeight.w700
                        : FontWeight.w600,
                    letterSpacing: -0.1,
                  )),
              child: Text(widget.label, maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}
