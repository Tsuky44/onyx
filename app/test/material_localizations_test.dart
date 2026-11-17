import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/l10n/material_localizations.dart';

/// Le menu copier/coller, les sélecteurs de date et la page des licences sont
/// écrits par Flutter : sans délégués, ils restent en anglais dans une app en
/// français (ADR-0047).
void main() {
  tearDown(AppLanguage.resetForTest);

  Future<String> copyLabel(WidgetTester tester, AppLanguage language) async {
    late String label;
    await tester.pumpWidget(MaterialApp(
      locale: language.locale,
      localizationsDelegates: kLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Builder(builder: (context) {
        label = MaterialLocalizations.of(context).copyButtonLabel;
        return const SizedBox.shrink();
      }),
    ));
    return label;
  }

  testWidgets('Material parle la langue de l’app', (tester) async {
    expect(await copyLabel(tester, AppLanguage.french), 'Copier');
    expect(await copyLabel(tester, AppLanguage.english), 'Copy');
  });

  test('les langues prises en charge sont celles de l’app', () {
    expect(kSupportedLocales.map((l) => l.languageCode),
        AppLanguage.values.map((l) => l.code));
  });
}
