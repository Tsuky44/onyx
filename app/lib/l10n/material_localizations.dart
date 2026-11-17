import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_language.dart';

/// Les textes que Flutter écrit lui-même (menu copier/coller, sélecteurs de
/// date, page des licences, étiquettes d'accessibilité) dans la langue de
/// l'app. Sans ces délégués, ils restent en anglais même quand l'interface est
/// en français. Voir l'ADR-0047.
const Iterable<LocalizationsDelegate<dynamic>> kLocalizationsDelegates =
    GlobalMaterialLocalizations.delegates;

/// Les langues de l'app, dans l'ordre de [AppLanguage].
final List<Locale> kSupportedLocales = [
  for (final language in AppLanguage.values) language.locale,
];
