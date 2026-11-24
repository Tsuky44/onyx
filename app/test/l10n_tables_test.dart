import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/l10n/en.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/otp.dart';
import 'package:onyx/models/request_catalog_filters.dart';
import 'package:onyx/models/server_activity.dart';
import 'package:onyx/screens/library/library_screen.dart';
import 'package:onyx/screens/player/player_shortcuts.dart';
import 'package:onyx/screens/requests/widgets/request_type_switch.dart';
import 'package:onyx/screens/settings/legal_document_screen.dart';
import 'package:onyx/screens/settings/widgets/about_group.dart';
import 'package:onyx/screens/settings/widgets/user_rights.dart';
import 'package:onyx/services/playback_preferences_storage.dart';
import 'package:onyx/utils/format.dart';
import 'package:onyx/widgets/global/detail_info_table.dart';
import 'package:onyx/models/media_share.dart';

/// `l10n_coverage_test.dart` ne voit que les littéraux passés à `tr('…')`. Ces
/// tables-ci sont lues par `tr(variable)` à l'affichage : leurs textes n'ont
/// aucun appel littéral, et un oubli resterait en français dans une interface
/// anglaise sans qu'aucun test ne le dise. Chaque table atteignable par un
/// `tr(variable)` figure donc ici (ADR-0047).
void _expectTranslated(String table, Iterable<String> keys) {
  final missing = keys.where((key) => !kEnglish.containsKey(key)).toList();
  expect(
    missing,
    isEmpty,
    reason: '$table : ajoute ces clés à lib/l10n/en.dart',
  );
}

void main() {
  tearDown(AppLanguage.resetForTest);

  test('les filtres du catalogue de demandes ont leur traduction', () {
    _expectTranslated(
      'requestCatalogSortOptions',
      requestCatalogSortOptions.map((o) => o.label),
    );
    _expectTranslated(
      'requestCatalogLanguageOptions',
      requestCatalogLanguageOptions.map((o) => o.label),
    );
    _expectTranslated(
      'requestCatalogRegions',
      requestCatalogRegions.map((o) => o.label),
    );
    _expectTranslated(
      'RequestTypeSwitch.tabs',
      RequestTypeSwitch.tabs.map((tab) => tab.label),
    );
  });

  test('les droits d’administration ont leur traduction', () {
    _expectTranslated('permissionLabels', permissionLabels.map((e) => e.$2));
    _expectTranslated('permissionsSummary', [
      'Administrateur',
      'Aucun droit',
      '{0} droits',
    ]);
  });

  test('la fiche des raccourcis du lecteur est traduite', () {
    _expectTranslated(
      'playerShortcutHelpRows (touches)',
      playerShortcutHelpRows.map((r) => r.$1),
    );
    _expectTranslated(
      'playerShortcutHelpRows (actions)',
      playerShortcutHelpRows.map((r) => r.$2),
    );
  });

  test('les statuts, langues et pays du cartel sont traduits', () {
    _expectTranslated('kDetailStatusLabels', kDetailStatusLabels.values);
    _expectTranslated('kDetailLanguages', kDetailLanguages.values);
    _expectTranslated('kDetailCountries', kDetailCountries.values);
    _expectTranslated('kLanguageNames', kLanguageNames.values);
  });

  test('les libellés d’énumérations sont traduits', () {
    // En français, `label` rend la clé telle qu'elle est écrite dans le code.
    _expectTranslated('OtpPolicy', OtpPolicy.values.map((v) => v.label));
    _expectTranslated(
      'ShareLifetime',
      ShareLifetime.values.map((v) => v.label),
    );
    _expectTranslated('PlayMethod', PlayMethod.values.map((v) => v.label));
    _expectTranslated(
      'LegalDocument',
      LegalDocument.values.map((v) => v.title),
    );
  });

  test('les tris et les langues audio de la bibliothèque sont traduits', () {
    _expectTranslated('librarySortLabels', librarySortLabels);
    _expectTranslated(
      'audioLanguageOptions',
      PlaybackPreferencesStorage.audioLanguageOptions.map((o) => o.label),
    );
  });

  test('les bibliothèques d’un ancien serveur et la page À propos', () {
    _expectTranslated(
      'MediaLibrary.legacy',
      MediaLibrary.legacy.map((library) => library.name),
    );
    _expectTranslated('AboutGroup', [
      AboutGroup.tmdbAttribution,
      AboutGroup.responsibility,
    ]);
    _expectTranslated('promptPassword', ['Nouveau mot de passe']);
  });

  test('les unités de taille de fichier se rendent en anglais', () {
    AppLanguage.notifier.value = AppLanguage.english;
    final rendered = [
      formatBytes(1),
      formatBytes(1500),
      formatBytes(1500000),
      formatBytes(1500000000),
      formatBytes(1500000000000),
    ];
    for (final text in rendered) {
      expect(
        text,
        matches(RegExp(r'\d (B|KB|MB|GB|TB)$')),
        reason: 'unité française restée telle quelle : $text',
      );
    }
  });
}
