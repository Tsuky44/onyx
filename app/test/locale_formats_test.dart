import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/screens/settings/widgets/settings_ui.dart';
import 'package:onyx/utils/format.dart';
import 'package:onyx/utils/long_date.dart';
import 'package:onyx/widgets/global/detail_info_table.dart';

void main() {
  tearDown(AppLanguage.resetForTest);

  void english() => AppLanguage.notifier.value = AppLanguage.english;

  final day = DateTime(2026, 10, 20);

  group('dates', () {
    test('en français', () {
      expect(formatLongDate(day), '20 octobre 2026');
      expect(formatDay(day), 'mardi 20 octobre');
      expect(formatDay(day, capitalize: true), 'Mardi 20 octobre');
      expect(formatShortDate(DateTime(2026, 9, 14)), '14 sept.');
      expect(formatReleaseDay('2024-03-12'), '12 mars 2024');
      expect(formatReleaseDay('2023-12-01'), '1 déc. 2023');
    });

    test('en anglais américain', () {
      english();
      expect(formatLongDate(day), 'October 20, 2026');
      expect(formatDay(day), 'Tuesday, October 20');
      expect(formatShortDate(DateTime(2026, 10, 3)), 'Oct 3');
      expect(formatReleaseDay('2024-03-12'), 'Mar 12, 2024');
    });
  });

  group('formatBytes', () {
    test(
      'virgule en français',
      () => expect(formatBytes(1500000000), '1,5 Go'),
    );
    test('point en anglais', () {
      english();
      expect(formatBytes(1500000000), '1.5 GB');
      expect(formatBytes(999), '999 B');
    });
  });

  group('formatMoney', () {
    test('en français', () {
      expect(formatMoney(1200000000), '1.2 Md \$US');
      expect(formatMoney(12000000), '12 M \$US');
      expect(formatMoney(500), '500 \$US');
      expect(formatMoney(null), '');
    });

    test('en anglais', () {
      english();
      expect(formatMoney(1200000000), '\$1.2B');
      expect(formatMoney(12000000), '\$12M');
      expect(formatMoney(500), '\$500');
      expect(formatMoney(0), '');
    });
  });
}
