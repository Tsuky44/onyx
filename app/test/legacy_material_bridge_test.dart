// Ce test lit ce que voit une dépendance restée sur l'ancien Material : il
// importe donc l'ancien Material lui aussi (ADR-0168, liste du test
// material_ui_migration_guard_test.dart).
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/theme/legacy_material_bridge.dart';

/// Ce que lit un widget de l'ancien Material placé sous l'app.
class _Seen {
  late legacy.ThemeData theme;
  legacy.MaterialLocalizations? localizations;
}

Future<_Seen> _pumpUnderApp(WidgetTester tester, {required bool bridged}) async {
  final seen = _Seen();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    builder: bridged
        ? (context, child) => LegacyMaterialBridge(child: child!)
        : null,
    home: Builder(builder: (context) {
      seen.theme = legacy.Theme.of(context);
      seen.localizations = Localizations.of<legacy.MaterialLocalizations>(
          context, legacy.MaterialLocalizations);
      return const SizedBox.shrink();
    }),
  ));
  return seen;
}

void main() {
  testWidgets(
      'sans le pont, l’ancien Material ne voit ni le thème ni les textes de '
      'l’app', (tester) async {
    final seen = await _pumpUnderApp(tester, bridged: false);

    // C'est la panne que le pont corrige : le thème clair par défaut.
    expect(seen.theme.colorScheme.primary, isNot(AppColors.primary));
    expect(seen.localizations, isNull);
  });

  testWidgets(
      'avec le pont, l’ancien Material voit les couleurs, la police et les '
      'textes de l’app', (tester) async {
    final seen = await _pumpUnderApp(tester, bridged: true);

    expect(seen.theme.colorScheme.brightness, Brightness.dark);
    expect(seen.theme.colorScheme.primary, AppColors.primary);
    expect(seen.theme.colorScheme.surface, AppColors.surface);
    expect(seen.theme.colorScheme.onSurface, AppColors.textPrimary);
    expect(seen.theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
    expect(seen.theme.textTheme.bodyMedium?.color, AppColors.textPrimary);
    // L'app de test n'a pas de langue : l'anglais par défaut. La langue de
    // l'app est vérifiée par material_localizations_test.dart.
    expect(seen.localizations?.backButtonTooltip, 'Back');
  });

  testWidgets('le pont ne recalcule pas l’ancien thème à chaque construction',
      (tester) async {
    // Par identité : deux thèmes recalculés seraient égaux (==).
    final themes = Set<legacy.ThemeData>.identity();
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => LegacyMaterialBridge(child: child!),
        home: Builder(builder: (context) {
          themes.add(legacy.Theme.of(context));
          return Text('$i');
        }),
      ));
    }
    expect(themes, hasLength(1));
  });
}
