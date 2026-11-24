import 'package:material_ui/material_ui.dart';

import 'app_language.dart';

/// Les textes propres de Material (copier/coller, infobulle du bouton
/// retour, page des licences, sélecteur de date…) dans la langue de l'app.
///
/// Jusqu'à l'ADR-0168, Material n'était pas traduit et restait en anglais
/// dans les deux langues (ADR-0047). Il suit désormais [AppLanguage] : les
/// deux `MaterialApp` prennent [delegates], [supportedLocales] et
/// [localeOf], et le pont de l'ancien Material (`LegacyMaterialBridge`) fait
/// de même pour les dépendances qui y sont restées.
///
/// La langue se change à chaud sans rien de plus : l'app entière est
/// reconstruite sous une nouvelle clé quand [AppLanguage.notifier] change
/// (`main.dart`).
abstract final class AppMaterialLocalizations {
  /// Les traductions de Material, de Cupertino et des widgets, celles de
  /// `material_ui`.
  static const List<LocalizationsDelegate<dynamic>> delegates =
      GlobalMaterialLocalizations.delegates;

  /// Les langues de l'app. L'anglais est l'américain, comme ses dates
  /// (`LocaleFormats`).
  static const List<Locale> supportedLocales = <Locale>[
    Locale('fr'),
    Locale('en', 'US'),
  ];

  static Locale localeOf(AppLanguage language) => switch (language) {
        AppLanguage.french => const Locale('fr'),
        AppLanguage.english => const Locale('en', 'US'),
      };
}
