import 'dart:ui';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/desktop_window.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/utils/window_controls.dart';
import 'package:onyx/widgets/global/glass_chrome.dart';
import 'package:onyx/widgets/global/window_caption_buttons.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    WindowFrameState frame = const WindowFrameState(),
  }) async {
    final calls = <String>[];
    // Monté comme dans la bande du haut : au-dessus du Navigator, donc sans
    // Overlay. Un widget qui en exige un (Tooltip) ferait échouer ces tests.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topRight,
          child: WindowCaptionButtons(
            state: ValueNotifier(frame),
            onMinimize: () => calls.add('minimize'),
            onToggleMaximize: () => calls.add('maximize'),
            onClose: () => calls.add('close'),
          ),
        ),
      ),
    );
    return calls;
  }

  Finder button(String label) => find.bySemanticsLabel(label);

  Color fillOf(WidgetTester tester, String label) {
    final box = tester.widget<AnimatedContainer>(find.descendant(
      of: button(label),
      matching: find.byType(AnimatedContainer),
    ));
    return (box.decoration! as BoxDecoration).color!;
  }

  testWidgets(
      'les contrôles suivent l\'ordre de Windows, fermer tout à droite, '
      'à la hauteur du champ Rechercher', (tester) async {
    await pump(tester);

    final minimize = tester.getRect(button('Réduire'));
    final maximize = tester.getRect(button('Agrandir'));
    final close = tester.getRect(button('Fermer'));

    expect(minimize.center.dx, lessThan(maximize.center.dx));
    expect(maximize.center.dx, lessThan(close.center.dx));
    expect(
      close.size,
      Size(
        WindowCaptionButtons.buttonWidth,
        GlassSearchInput.heightFor(large: false),
      ),
    );
  });

  testWidgets('chaque bouton déclenche son action', (tester) async {
    final calls = await pump(tester);

    await tester.tap(button('Réduire'));
    await tester.tap(button('Agrandir'));
    await tester.tap(button('Fermer'));

    expect(calls, ['minimize', 'maximize', 'close']);
  });

  testWidgets('au repos, rien que les symboles ; Fermer rougit au survol',
      (tester) async {
    await pump(tester);
    expect(fillOf(tester, 'Fermer'), Colors.transparent);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(button('Fermer')));
    await tester.pumpAndSettle();

    expect(fillOf(tester, 'Fermer'), AppColors.windowClose);
    expect(fillOf(tester, 'Réduire'), Colors.transparent);
  });

  testWidgets('une fenêtre agrandie propose « Restaurer »', (tester) async {
    await pump(tester, frame: const WindowFrameState(maximized: true));

    expect(button('Restaurer'), findsOneWidget);
    expect(button('Agrandir'), findsNothing);
  });

  group('un en-tête qui porte les contrôles efface la bande du haut', () {
    testWidgets('tant qu\'il est à l\'écran', (tester) async {
      await tester.pumpWidget(
        const WindowCaptionHost(child: SizedBox.shrink()),
      );
      await tester.pump();
      expect(windowCaptionHosted.value, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(windowCaptionHosted.value, isFalse);
    });

    testWidgets('mais plus sous une page opaque, qui coupe ses animations',
        (tester) async {
      await tester.pumpWidget(const TickerMode(
        enabled: false,
        child: WindowCaptionHost(child: SizedBox.shrink()),
      ));
      await tester.pump();
      expect(windowCaptionHosted.value, isFalse);

      await tester.pumpWidget(const TickerMode(
        enabled: true,
        child: WindowCaptionHost(child: SizedBox.shrink()),
      ));
      await tester.pump();
      expect(windowCaptionHosted.value, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
