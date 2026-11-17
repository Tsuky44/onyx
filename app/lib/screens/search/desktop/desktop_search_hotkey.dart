import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ctrl K (⌘ K sur Mac) et « / » : ouvrir la recherche du bureau de
/// n'importe où dans l'app.
///
/// Les touches sont posées avec celles de `MaterialApp` (`main.dart`), le
/// seul jeu de raccourcis de l'app hors dpad (ADR-0110) : pas de second
/// `Shortcuts` ni de gestionnaire de touches à côté. L'action ne fait rien
/// tant que le champ de l'en-tête du bureau ne s'est pas inscrit
/// ([register]) : sur un téléviseur et sur un téléphone, la touche passe son
/// chemin. Voir ADR-0139.
abstract final class DesktopSearchHotkey {
  /// Les touches, à joindre à celles de `MaterialApp`.
  ///
  /// « / » est un caractère, pas une touche : sur un clavier AZERTY il se
  /// tape avec Maj, et `SingleActivator(slash)` ne l'aurait jamais vu.
  static Map<ShortcutActivator, Intent> get bindings =>
      const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            OpenSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            OpenSearchIntent(),
        CharacterActivator('/'): OpenSearchIntent(fromSlash: true),
      };

  /// L'action, à joindre à celles de `MaterialApp`.
  static Action<OpenSearchIntent> get action => _OpenSearchAction();

  static DesktopSearchSummoner? _summoner;

  /// Le champ de l'en-tête du bureau s'inscrit à son montage.
  static void register(DesktopSearchSummoner summoner) => _summoner = summoner;

  static void unregister(DesktopSearchSummoner summoner) {
    if (identical(_summoner, summoner)) _summoner = null;
  }
}

/// Qui répond au raccourci : le champ de l'en-tête du bureau.
abstract interface class DesktopSearchSummoner {
  /// Faux quand la recherche ne peut pas s'ouvrir ici : lecteur plein écran,
  /// dialogue ou menu ouvert par-dessus la coquille.
  bool get canSummon;

  void summon();
}

class OpenSearchIntent extends Intent {
  const OpenSearchIntent({this.fromSlash = false});

  /// Vrai pour « / », qui reste un caractère dans un champ de saisie.
  final bool fromSlash;
}

class _OpenSearchAction extends Action<OpenSearchIntent> {
  @override
  bool isEnabled(OpenSearchIntent intent) {
    final summoner = DesktopSearchHotkey._summoner;
    if (summoner == null || !summoner.canSummon) return false;
    // Désactivée, l'action rend la touche : le champ focalisé reçoit « / »
    // comme n'importe quel autre caractère.
    return !intent.fromSlash || !_typingInAField();
  }

  @override
  Object? invoke(OpenSearchIntent intent) {
    DesktopSearchHotkey._summoner?.summon();
    return null;
  }

  static bool _typingInAField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorStateOfType<EditableTextState>() != null;
  }
}
