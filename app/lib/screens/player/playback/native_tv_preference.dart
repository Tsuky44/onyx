import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_platform.dart';

/// Quel lecteur prend l'écran sur Apple TV.
enum NativeTvPlayerMode {
  /// L'écran natif d'Apple TV (`AVPlayerViewController`).
  native,

  /// L'interface Flutter d'Onyx.
  onyx,
}

/// Le réglage « Lecteur Apple TV » de cet appareil.
///
/// Un réglage de l'appareil et non du compte : il dépend de la télécommande
/// et du téléviseur au bout desquels on se trouve (ADR-0056).
abstract final class NativeTvPlayerPreference {
  static const String _key = 'native_tv_player_mode';

  /// Le défaut. Reste sur Onyx tant que le natif n'est pas validé sur
  /// appareil ; passer à `native` est le seul changement à faire ensuite.
  static const NativeTvPlayerMode defaultMode = NativeTvPlayerMode.onyx;

  static NativeTvPlayerMode _mode = defaultMode;

  static NativeTvPlayerMode get mode => _mode;

  /// Le réglage n'a de sens que sur Apple TV : ailleurs il n'y a pas d'écran
  /// natif à choisir.
  static bool isAvailable({required bool isTvOS}) => isTvOS;

  /// Le natif ne s'active que sur Apple TV et si l'utilisateur l'a choisi.
  /// Ce qui dépend du média passe ensuite par `nativeTvFallbackFor`.
  static bool isEligible({
    required bool isTvOS,
    required NativeTvPlayerMode mode,
  }) =>
      isTvOS && mode == NativeTvPlayerMode.native;

  /// Lit le réglage enregistré. Une fois, au démarrage.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _mode = NativeTvPlayerMode.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => defaultMode,
      );
    } catch (_) {
      _mode = defaultMode;
    }
  }

  /// Prend effet à la prochaine lecture : le présentateur se décide à
  /// l'ouverture du lecteur.
  static Future<void> setMode(NativeTvPlayerMode value) async {
    _mode = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (_) {
      // Faute de disque, le réglage vaut pour la séance.
    }
  }

  static bool get eligibleHere =>
      isEligible(isTvOS: AppPlatform.isTvOS, mode: _mode);

  static void resetForTest() => _mode = defaultMode;
}
