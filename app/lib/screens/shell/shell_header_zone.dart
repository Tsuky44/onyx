import 'package:flutter/widgets.dart';

import '../../tv/nav/onyx_dpad.dart' show TvNavScope;
import '../../tv/nav/tv_region.dart';
import '../../tv/tv_focus_entry.dart';

/// La zone de l'en-tête du shell (onglets, recherche, compte), selon le
/// système de navigation monté (ADR-0110).
///
/// - **Sous dpad**, une zone d'onglets ([TvRegion.tabs]) : on y entre par
///   l'onglet affiché, que `GlassNavTab` marque comme entrée, et gauche/droite
///   s'arrêtent à ses bords.
/// - **Avec l'ancien système**, un groupe de parcours à lui, dans l'ordre de
///   ses widgets : l'en-tête ne subit plus l'ordre du contenu dessous. Haut
///   depuis le contenu arrive sur l'onglet affiché ([entryFor]), comme sur
///   Android TV : le parcours choisissait l'onglet le plus proche à la
///   verticale, et depuis le bouton du bandeau on montait sur « Films » en
///   étant sur l'accueil. La recherche et le compte, à droite, restent
///   atteignables tels quels.
///
/// Les deux ne cohabitent jamais : la politique du groupe déciderait des
/// flèches à la place de dpad. Sorti de `main_shell.dart` pour que les cartes
/// de navigation (`shell_navigation_map_test`) éprouvent ce que l'app monte.
class ShellHeaderZone extends StatefulWidget {
  const ShellHeaderZone({
    super.key,
    required this.focusNode,
    required this.entryFor,
    required this.child,
  });

  /// L'en-tête entier, sans jamais prendre le focus lui-même : Retour s'en
  /// sert pour savoir si la télécommande y est. Le même pour toute la vie de
  /// la zone : c'est sous lui que l'ancien système l'inscrit.
  final FocusNode focusNode;

  /// Ancien système : l'onglet où entrer quand le parcours a trouvé [landed]
  /// dans l'en-tête, ou nul pour garder [landed] (la recherche, le compte).
  final FocusNode? Function(FocusNode landed) entryFor;

  final Widget child;

  @override
  State<ShellHeaderZone> createState() => _ShellHeaderZoneState();
}

class _ShellHeaderZoneState extends State<ShellHeaderZone> {
  /// Gardée d'un build à l'autre pour que le groupe ne change pas de politique
  /// en cours de route.
  final TvWidgetOrderTraversalPolicy _policy = TvWidgetOrderTraversalPolicy();

  // Inscrite dans les deux systèmes : sous dpad, rien ne consulte les entrées
  // de l'ancien (sa politique n'est pas montée), et l'inscription reste inerte.
  @override
  void initState() {
    super.initState();
    TvFocusEntries.register(widget.focusNode, _enter);
  }

  @override
  void dispose() {
    TvFocusEntries.unregister(widget.focusNode);
    super.dispose();
  }

  /// Réponse de zone, donnée avant que le focus ne se pose
  /// ([TvFocusEntries]) : l'ancienne rustine attendait le focus sur le
  /// mauvais onglet pour le déplacer ensuite, soit deux pas à chaque montée.
  FocusNode? _enter(FocusNode landed, FocusNode? from) {
    if (from != null && from.ancestors.contains(widget.focusNode)) return null;
    final entry = widget.entryFor(landed);
    if (entry == null || entry.context == null) return null;
    return entry;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: false,
      skipTraversal: true,
      child: TvNavScope.isActive(context)
          ? TvRegion.tabs(id: 'shell/header', child: widget.child)
          : FocusTraversalGroup(policy: _policy, child: widget.child),
    );
  }
}
