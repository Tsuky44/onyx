import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/onyx_menu.dart';
import 'package:onyx/widgets/global/onyx_menu_panel.dart';

/// Monte un [OnyxMenuButton] à [alignment] d'un écran de 800 × 600.
Future<void> _mount(
  WidgetTester tester, {
  required List<OnyxMenuItem<String?>> items,
  ValueChanged<String?>? onSelected,
  Alignment alignment = Alignment.topLeft,
  bool tv = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    TvScope(
      isTv: tv,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: alignment,
            child: OnyxMenuButton<String?>(
              tooltip: 'Menu',
              icon: AppIcons.more,
              items: items,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un choix rend sa valeur, même nulle', (tester) async {
    final picks = <String?>[];
    await _mount(
      tester,
      items: const [
        OnyxMenuItem(value: null, label: 'Automatique'),
        OnyxMenuItem(value: 'fr', label: 'Français'),
      ],
      onSelected: picks.add,
    );

    await _open(tester);
    expect(find.byType(OnyxMenuPanel<String?>), findsOneWidget);
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(picks, ['fr']);
    expect(find.byType(OnyxMenuPanel<String?>), findsNothing);

    await _open(tester);
    await tester.tap(find.text('Automatique'));
    await tester.pumpAndSettle();
    expect(picks, ['fr', null]);
  });

  testWidgets('fermer le menu sans choix ne rend rien', (tester) async {
    final picks = <String?>[];
    await _mount(
      tester,
      items: const [OnyxMenuItem(value: 'a', label: 'A')],
      onSelected: picks.add,
    );
    await _open(tester);
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.byType(OnyxMenuPanel<String?>), findsNothing);
    expect(picks, isEmpty);
  });

  testWidgets('une ligne destructive est rouge, rangée sous un filet',
      (tester) async {
    await _mount(
      tester,
      items: const [
        OnyxMenuItem(value: 'export', label: 'Exporter'),
        OnyxMenuItem(value: 'clear', label: 'Vider', destructive: true),
      ],
    );
    await _open(tester);

    final clear = tester.widget<Text>(find.text('Vider'));
    final export = tester.widget<Text>(find.text('Exporter'));
    expect(clear.style?.color, AppColors.error);
    expect(export.style?.color, isNot(AppColors.error));
    // Le panneau mesure ses lignes et le filet sans attendre la mise en page.
    const metrics = OnyxMenuMetrics(compact: false);
    expect(tester.getTopLeft(find.text('Vider')).dy,
        greaterThan(tester.getBottomLeft(find.text('Exporter')).dy + 9));
    expect(
      tester.getSize(find.byType(OnyxMenuPanel<String?>)).height,
      metrics.heightOf(const [
        OnyxMenuItem(value: 'export', label: 'Exporter'),
        OnyxMenuItem(value: 'clear', label: 'Vider', destructive: true),
      ]),
    );
  });

  testWidgets('un menu de choix coche la valeur et réserve la coche partout',
      (tester) async {
    await _mount(
      tester,
      items: const [
        OnyxMenuItem(value: 'a', label: 'Récents'),
        OnyxMenuItem(value: 'b', label: 'A → Z', checked: true),
        OnyxMenuItem(value: 'c', label: 'Note'),
      ],
    );
    await _open(tester);

    final checks = tester
        .widgetList<Icon>(find.byIcon(AppIcons.check))
        .map((i) => i.color)
        .toList();
    expect(checks, hasLength(3), reason: 'la place de la coche est réservée');
    expect(checks.where((c) => c != Colors.transparent), hasLength(1));
    expect(checks[1], isNot(Colors.transparent));
  });

  testWidgets('une longue liste s’ouvre défilée sur la valeur cochée',
      (tester) async {
    await _mount(
      tester,
      alignment: Alignment.center,
      items: [
        for (var h = 0; h < 24; h++)
          OnyxMenuItem(value: '$h', label: '$h:00', checked: h == 20),
      ],
    );
    await _open(tester);
    final row = tester.getRect(find.text('20:00'));
    expect(row.top, greaterThanOrEqualTo(0));
    expect(row.bottom, lessThanOrEqualTo(600));
  });

  testWidgets('en bas d’écran, le menu s’ouvre au-dessus du bouton',
      (tester) async {
    final items = [
      for (var i = 0; i < 5; i++)
        OnyxMenuItem<String?>(value: '$i', label: 'Ligne $i'),
    ];
    await _mount(tester, items: items, alignment: Alignment.bottomRight);
    await _open(tester);

    final button = tester.getRect(find.byType(IconButton));
    final panel = tester.getRect(find.byType(OnyxMenuPanel<String?>));
    expect(panel.bottom, lessThanOrEqualTo(button.top));
    // Côté centre de l'écran : le bord droit sur celui du bouton, dans
    // l'écran.
    expect(panel.right, lessThanOrEqualTo(800 - 12));
    expect(panel.left, greaterThanOrEqualTo(12));
  });

  testWidgets('en haut à gauche, le menu s’ouvre dessous, bord gauche aligné',
      (tester) async {
    await _mount(
      tester,
      items: const [OnyxMenuItem(value: 'a', label: 'A')],
    );
    await _open(tester);
    final button = tester.getRect(find.byType(IconButton));
    final panel = tester.getRect(find.byType(OnyxMenuPanel<String?>));
    expect(panel.top, greaterThanOrEqualTo(button.bottom));
    expect(panel.left, moreOrLessEquals(12));
  });

  testWidgets('sur un téléviseur, le menu reste celui de Material',
      (tester) async {
    await _mount(
      tester,
      tv: true,
      items: const [OnyxMenuItem(value: 'a', label: 'A')],
    );
    expect(find.byType(PopupMenuButton<({String? value})>), findsOneWidget);
    await _open(tester);
    expect(find.byType(OnyxMenuPanel<String?>), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });
}
