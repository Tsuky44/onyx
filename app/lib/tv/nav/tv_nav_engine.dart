import 'package:flutter/foundation.dart';

/// Le système de navigation au D-pad que l'app monte (ADR-0110, phase 2).
///
/// Le temps de la bêta de la phase 2, l'ancien système et dpad coexistent dans
/// le code, jamais dans la même app : le choix se fait à la compilation,
/// `--dart-define=ONYX_TV_NAV=dpad`, et se lit **une fois**, au démarrage, par
/// `main.dart`. Il décide seulement de ce qui se monte à la racine (`OnyxDpad`
/// ou l'ancienne politique de parcours) ; `TvFocusable` et `TvRegion` suivent
/// ce qui est monté (`TvNavScope`), sans relire le drapeau.
///
/// Par défaut, `legacy` : sans le drapeau, l'app est celle de `main` avant la
/// refonte, et revenir en arrière ne demande ni revert ni nouvelle version du
/// code. Le drapeau disparaît avant la phase 3.
enum TvNavEngine {
  /// L'ancien système : `TvTraversalPolicy`, `TvDirectionalFocusAction`,
  /// `TvFocusMemory`, `TvFocusGuard`.
  legacy,

  /// dpad 3.3.0 derrière `OnyxDpad`, `TvBack` et `TvArrowGate`.
  dpad;

  /// La valeur brute du drapeau de compilation.
  static const String _define = String.fromEnvironment(
    'ONYX_TV_NAV',
    defaultValue: 'legacy',
  );

  /// Lu une seule fois : un moteur qui changerait en cours de route
  /// mélangerait deux systèmes de parcours dans le même arbre.
  static final TvNavEngine _compiled = parse(_define);

  /// Remplace le drapeau dans les tests, qui tournent sans `--dart-define`.
  @visibleForTesting
  static TvNavEngine? debugOverride;

  /// Le moteur de cette compilation.
  static TvNavEngine get current => debugOverride ?? _compiled;

  /// [value] tel qu'écrit dans `--dart-define`. Une valeur inconnue retombe
  /// sur [legacy] : une faute de frappe dans un script de build ne doit pas
  /// livrer le moteur en bêta.
  static TvNavEngine parse(String value) => switch (value.trim()) {
        'dpad' => TvNavEngine.dpad,
        _ => TvNavEngine.legacy,
      };
}
