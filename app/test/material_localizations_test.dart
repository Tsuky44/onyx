@TestOn('vm')
library;

import 'dart:io';

// Ce test lit aussi ce que voit une dépendance restée sur l'ancien Material,
// à travers le pont (ADR-0168, liste du test
// material_ui_migration_guard_test.dart).
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/l10n/material_localizations.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/theme/legacy_material_bridge.dart';

/// Les textes de Material lus sous l'app, côté `material_ui` et côté ancien
/// Material (à travers le pont).
class _Seen {
  late MaterialLocalizations modern;
  legacy.MaterialLocalizations? old;
}

Widget _app(AppLanguage language, _Seen seen) => MaterialApp(
      key: ValueKey(language),
      theme: AppTheme.dark,
      locale: AppMaterialLocalizations.localeOf(language),
      supportedLocales: AppMaterialLocalizations.supportedLocales,
      localizationsDelegates: AppMaterialLocalizations.delegates,
      builder: (context, child) => LegacyMaterialBridge(child: child!),
      home: Builder(builder: (context) {
        seen.modern = MaterialLocalizations.of(context);
        seen.old = Localizations.of<legacy.MaterialLocalizations>(
            context, legacy.MaterialLocalizations);
        return const SizedBox.shrink();
      }),
    );

void main() {
  const expected = {
    AppLanguage.french: (
      back: 'Retour',
      paste: 'Coller',
      copy: 'Copier',
      licenses: 'Licences',
      datePicker: 'Sélectionner une date',
    ),
    AppLanguage.english: (
      back: 'Back',
      paste: 'Paste',
      copy: 'Copy',
      licenses: 'Licenses',
      datePicker: 'Select date',
    ),
  };

  for (final MapEntry(key: language, value: texts) in expected.entries) {
    testWidgets('Material parle ${language.nativeName}, dépendances comprises',
        (tester) async {
      final seen = _Seen();
      await tester.pumpWidget(_app(language, seen));

      expect(seen.modern.backButtonTooltip, texts.back);
      expect(seen.modern.pasteButtonLabel, texts.paste);
      expect(seen.modern.copyButtonLabel, texts.copy);
      expect(seen.modern.licensesPageTitle, texts.licenses);
      expect(seen.modern.datePickerHelpText, texts.datePicker);
      // Une dépendance restée sur l'ancien Material lit la même langue.
      expect(seen.old?.backButtonTooltip, texts.back);
      expect(seen.old?.pasteButtonLabel, texts.paste);
    });
  }

  testWidgets('changer de langue à chaud retraduit Material', (tester) async {
    final seen = _Seen();
    await tester.pumpWidget(_app(AppLanguage.french, seen));
    expect(seen.modern.backButtonTooltip, 'Retour');

    // Comme `main.dart` : l'app est reconstruite sous la clé de la langue.
    await tester.pumpWidget(_app(AppLanguage.english, seen));
    expect(seen.modern.backButtonTooltip, 'Back');
    expect(seen.old?.backButtonTooltip, 'Back');
  });

  testWidgets('le sélecteur de date s’affiche dans la langue de l’app',
      (tester) async {
    for (final (language, help, cancel) in const [
      (AppLanguage.french, 'Sélectionner une date', 'Annuler'),
      (AppLanguage.english, 'Select date', 'Cancel'),
    ]) {
      late BuildContext appContext;
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(language),
        theme: AppTheme.dark,
        locale: AppMaterialLocalizations.localeOf(language),
        supportedLocales: AppMaterialLocalizations.supportedLocales,
        localizationsDelegates: AppMaterialLocalizations.delegates,
        home: Builder(builder: (context) {
          appContext = context;
          return const SizedBox.shrink();
        }),
      ));
      showDatePicker(
        context: appContext,
        initialDate: DateTime(2026, 11, 24),
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      );
      await tester.pumpAndSettle();

      expect(find.text(help), findsOneWidget);
      expect(find.text(cancel), findsOneWidget);
    }
  });

  test('chaque MaterialApp de l’app suit la langue de l’app', () {
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!RegExp(r'\bMaterialApp\(').hasMatch(source)) continue;
      final wired = source.contains('AppMaterialLocalizations.delegates') &&
          source.contains('AppMaterialLocalizations.supportedLocales') &&
          source.contains('AppMaterialLocalizations.localeOf(');
      if (!wired) missing.add(entity.path.replaceAll('\\', '/'));
    }

    expect(
      missing,
      isEmpty,
      reason: 'Sans `localizationsDelegates`, `supportedLocales` et `locale` '
          'tirés d’`AppMaterialLocalizations`, les textes de Material '
          'retombent en anglais dans l’app française (ADR-0168) :\n\n'
          '${missing.join('\n')}',
    );
  });
}
