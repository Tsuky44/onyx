import 'dart:async';

import 'package:flutter/foundation.dart';

import '../widgets/onyx/onyx_tabs.dart';
import 'use_episodes_panel.dart';

/// L'onglet du lecteur dont le volet est à l'écran (ADR-0130).
///
/// Une seule vérité pour les deux présentations : le volet posé sous la barre
/// d'un téléviseur, la feuille du bas des écrans à souris et à doigt. La liste
/// des épisodes suit son onglet : chargée quand il arrive, rangée quand il
/// part, pour que le lecteur n'interroge le serveur que devant quelqu'un qui
/// regarde la liste.
class PlayerTabsController extends ChangeNotifier {
  PlayerTabsController({
    required EpisodesPanelController episodes,
    required String Function() showTitle,
    required void Function(bool isOpen) onOpenChanged,
  })  : _episodes = episodes,
        _showTitle = showTitle,
        _onOpenChanged = onOpenChanged;

  final EpisodesPanelController _episodes;
  final String Function() _showTitle;

  /// Le volet vient de s'ouvrir ou de se fermer : le chrome se tient affiché
  /// tant qu'il est là, et son compte à rebours repart ensuite.
  final void Function(bool isOpen) _onOpenChanged;

  OnyxTab? _open;

  OnyxTab? get open => _open;
  bool get isOpen => _open != null;

  /// Ouvre [tab], ou ferme le volet avec `null`.
  void show(OnyxTab? tab) {
    if (tab == _open) return;
    final wasOpen = isOpen;
    _open = tab;
    if (tab == OnyxTab.episodes) {
      unawaited(_episodes.open(showTitle: _showTitle()));
    } else {
      _episodes.close();
    }
    notifyListeners();
    if (wasOpen != isOpen) _onOpenChanged(isOpen);
  }

  /// Ferme le volet. Rend vrai s'il était ouvert, pour que Retour s'arrête là.
  bool close() {
    if (!isOpen) return false;
    show(null);
    return true;
  }
}
