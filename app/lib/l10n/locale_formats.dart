import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app_language.dart';

/// Les formats qui changent d'une langue à l'autre : dates, séparateur
/// décimal, montants. Une langue de plus se règle ici et nulle part ailleurs
/// (ADR-0047) : les appelants ne testent jamais « si anglais ».
///
/// Les dates passent par les squelettes d'intl (`yMMMMd`…), qui donnent
/// « 20 octobre 2026 » en français et « October 20, 2026 » en anglais.
/// L'anglais est l'américain (`en_US`), choix du lot B.
abstract final class LocaleFormats {
  /// Charge les données de date de chaque langue de l'app. À appeler au
  /// démarrage, avant le premier écran, et dans les tests. Les données sont
  /// compilées dans l'application : pas d'accès réseau, web compris.
  static Future<void> initialize() async {
    for (final language in AppLanguage.values) {
      await initializeDateFormatting(_localeName(language));
    }
  }

  static String _localeName(AppLanguage language) => switch (language) {
        AppLanguage.french => 'fr',
        AppLanguage.english => 'en_US',
      };

  static String _date(String skeleton, DateTime date) =>
      DateFormat(skeleton, _localeName(AppLanguage.current)).format(date);

  /// « 20 octobre 2026 » / « October 20, 2026 ».
  static String longDate(DateTime date) => _date('yMMMMd', date);

  /// « 12 mars 2024 », « 1 déc. 2023 » / « Mar 12, 2024 ».
  static String mediumDate(DateTime date) => _date('yMMMd', date);

  /// « 14 sept. » / « Sep 14 » : pour les axes de graphique.
  static String shortDate(DateTime date) => _date('MMMd', date);

  /// « lundi 20 octobre » / « Monday, October 20 ».
  static String weekdayDate(DateTime date) => _date('MMMMEEEEd', date);

  /// « septembre 2026 » / « September 2026 ».
  static String monthYear(DateTime date) => _date('yMMMM', date);

  /// « mars » / « March » : un mois seul, pour le Rétro.
  static String month(DateTime date) => _date('LLLL', date);

  /// « 4 820 » / « 4,820 » : un entier avec ses milliers séparés. L'espace
  /// fine insécable du français devient une espace insécable ordinaire : la
  /// police de l'app n'a pas la fine, et le chiffre se collait.
  static String integer(int value) =>
      NumberFormat.decimalPattern(_localeName(AppLanguage.current))
          .format(value)
          .replaceAll('\u202F', '\u00A0');

  /// « 15 janvier » / « January 15 » : un jour du mois, sans l'année.
  static String dayMonth(DateTime date) => _date('MMMMd', date);

  /// « 23:47 » : une heure seule, sur 24 heures.
  static String time(DateTime date) => _date('Hm', date);

  /// « 1 janv. · 23:47 » / « Jan 1 · 23:47 ».
  static String shortDateTime(DateTime date) =>
      '${_date('MMMd', date)} · ${_date('Hm', date)}';

  /// Sépare la partie décimale d'un nombre déjà formaté avec un point.
  static String decimal(String dotted) => switch (AppLanguage.current) {
        AppLanguage.french => dotted.replaceAll('.', ','),
        AppLanguage.english => dotted,
      };

  /// Un montant en dollars : « 1.2 Md $US », « 12 M $US », « 500 $US » en
  /// français ; « $1.2B », « $12M », « $500 » en anglais.
  static String dollars(int amount) {
    final english = AppLanguage.current == AppLanguage.english;
    if (amount >= 1000000000) {
      // Point en français aussi : le format d'origine, conservé tel quel.
      final value = (amount / 1000000000.0).toStringAsFixed(1);
      return english ? '\$${value}B' : '$value Md \$US';
    }
    if (amount >= 1000000) {
      final value = (amount / 1000000.0).round();
      return english ? '\$${value}M' : '$value M \$US';
    }
    return english ? '\$$amount' : '$amount \$US';
  }
}
