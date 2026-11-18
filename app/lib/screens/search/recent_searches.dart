import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/auth_provider.dart';

/// Les dernières recherches d'un profil, proposées quand le champ est vide.
///
/// Rangées par profil et par serveur : sur un ordinateur de famille, chacun
/// ne retrouve que les siennes. Une recherche n'entre ici que lorsqu'elle a
/// servi (un titre ouvert depuis ses résultats), pas à chaque frappe : « D »,
/// « Du », « Dun » n'ont rien à y faire.
class RecentSearches extends ChangeNotifier {
  RecentSearches(this.profileKey) {
    _load();
  }

  /// `"<serveur>:<profil>"`, ou null avant la connexion : rien n'est alors
  /// retenu.
  final String? profileKey;

  /// La clé du profil ouvert, que [context] suit : un changement de profil
  /// ou de serveur reconstruit l'appelant, qui recharge alors l'historique.
  static String? watchProfileKey(BuildContext context) =>
      context.select<AuthProvider, String?>((auth) {
        final server = auth.activeServer?.id;
        final user = auth.currentUser?.id;
        return server == null || user == null ? null : '$server:$user';
      });

  /// Assez pour retrouver ce qu'on cherchait cette semaine, pas au point de
  /// pousser les derniers ajouts sous le pli.
  static const int max = 6;

  /// Le nom d'avant le partage avec le téléphone : le garder conserve
  /// l'historique déjà retenu sur le bureau.
  static const String _prefix = 'desktop_recent_searches/';

  List<String> _items = const [];
  bool _disposed = false;

  List<String> get items => _items;

  String? get _key => profileKey == null ? null : '$_prefix$profileKey';

  Future<void> _load() async {
    final key = _key;
    if (key == null) return;
    try {
      final saved = (await SharedPreferences.getInstance()).getStringList(key);
      if (_disposed || saved == null) return;
      _items = List.unmodifiable(saved.take(max));
      notifyListeners();
    } catch (error) {
      // Sans préférences lisibles, la recherche marche sans historique : rien
      // à montrer à l'utilisateur pour si peu.
      debugPrint('RecentSearches: lecture impossible ($error)');
    }
  }

  /// [query] vient de servir : elle passe en tête, sans doublon.
  void remember(String query) {
    final text = query.trim();
    if (text.isEmpty || _key == null) return;
    final folded = text.toLowerCase();
    _items = List.unmodifiable([
      text,
      for (final item in _items)
        if (item.toLowerCase() != folded) item,
    ].take(max));
    notifyListeners();
    _save();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items = const [];
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    final key = _key;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, _items);
    } catch (error) {
      // L'historique reste en mémoire pour la session ; il ne survivra
      // simplement pas au redémarrage.
      debugPrint('RecentSearches: écriture impossible ($error)');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
