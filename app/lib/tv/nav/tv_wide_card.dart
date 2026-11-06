import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

/// Une carte qui prend toute la largeur de la page, sous dpad
/// (`TvFocusable.wide`) : le bandeau « Reprendre » d'une lecture en cours
/// ailleurs, posé entre le bouton du bandeau de l'accueil et la première
/// rangée.
///
/// Le parcours de dpad garde, entre deux cibles du faisceau, la plus proche
/// *en travers*, au centre près. Depuis un bouton calé à gauche, le centre
/// d'une carte large est à des centaines de pixels : Bas sautait la carte
/// pour l'affiche du dessous, Haut la sautait pour le bouton du dessus (vu
/// dans `remote_playback_banner_focus_test`). Une porte invisible au quart
/// gauche de la carte est assez proche ; elle vit dans une zone dont la
/// carte est l'entrée, et dpad, qui trouve la porte, pose le focus sur la
/// carte en un seul `requestFocus`. Depuis la carte, la porte n'est ni
/// au-dessus, ni au-dessous, ni sur un côté : elle ne fait jamais d'arrêt.
class TvWideCard extends StatefulWidget {
  const TvWideCard({super.key, required this.card, required this.child});

  /// Le nœud de la carte, celui que la porte rend.
  final FocusNode card;

  /// La carte, marquée `entry`.
  final Widget child;

  @override
  State<TvWideCard> createState() => _TvWideCardState();
}

class _TvWideCardState extends State<TvWideCard> {
  final FocusNode _gate = FocusNode(debugLabel: 'tv-wide-card-gate');

  @override
  void dispose() {
    _gate.dispose();
    super.dispose();
  }

  /// La porte n'a rien à montrer : si quelque chose la focalise malgré tout
  /// (la restauration de dpad, qui ne connaît pas les zones), elle rend la
  /// main à la carte.
  void _onGateFocus(bool focused) {
    if (focused && _gate.hasPrimaryFocus) widget.card.requestFocus();
  }

  @override
  Widget build(BuildContext context) => DpadRegion(
        enter: DpadEnterBehavior.entry,
        debugLabel: 'wide-card',
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: 0.25,
                  heightFactor: 1,
                  child: Focus(
                    focusNode: _gate,
                    includeSemantics: false,
                    onFocusChange: _onGateFocus,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
