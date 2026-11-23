import 'package:flutter/gestures.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/smooth_wheel_scroll.dart';

class _Behavior extends MaterialScrollBehavior {
  const _Behavior(this.enabled);
  final bool enabled;
  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      SmoothWheelScroll(details: details, enabled: enabled, child: child);
}

Future<ScrollController> _pump(WidgetTester tester,
    {bool enabled = true}) async {
  final controller = ScrollController();
  await tester.pumpWidget(MaterialApp(
    scrollBehavior: _Behavior(enabled),
    home: ListView.builder(
      controller: controller,
      itemCount: 100,
      itemExtent: 100,
      itemBuilder: (_, i) => Text('$i'),
    ),
  ));
  return controller;
}

Future<void> _wheel(WidgetTester tester, double dy) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  pointer.hover(const Offset(200, 300));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
}

void main() {
  test('seuls les gros deltas entiers sont des crans de molette', () {
    expect(SmoothWheelScroll.isWheelNotch(100), isTrue);
    expect(SmoothWheelScroll.isWheelNotch(-120), isTrue);
    expect(SmoothWheelScroll.isWheelNotch(3.5), isFalse);
    expect(SmoothWheelScroll.isWheelNotch(12), isFalse);
    expect(SmoothWheelScroll.isWheelNotch(100.5), isFalse);
  });

  testWidgets('un cran glisse vers sa cible au lieu de sauter', (tester) async {
    final c = await _pump(tester);
    await _wheel(tester, 100);
    expect(c.offset, 0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.offset, greaterThan(0));
    expect(c.offset, lessThan(100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.offset, 100);
  });

  testWidgets('les crans rapides se cumulent', (tester) async {
    final c = await _pump(tester);
    await _wheel(tester, 100);
    await tester.pump(const Duration(milliseconds: 16));
    await _wheel(tester, 100);
    await _wheel(tester, 100);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.offset, 300);
  });

  testWidgets('les petits deltas du trackpad restent à Flutter',
      (tester) async {
    final c = await _pump(tester);
    await _wheel(tester, 7.5);
    expect(c.offset, 7.5);
  });

  testWidgets('Ctrl enfoncé : pas de lissage (zoom de grille)', (tester) async {
    final c = await _pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await _wheel(tester, 100);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(seconds: 1));
    expect(c.offset, 100); // Flutter l'a pris d'un coup.
  });

  testWidgets('désactivé (natif) : Flutter garde la main', (tester) async {
    final c = await _pump(tester, enabled: false);
    await _wheel(tester, 100);
    expect(c.offset, 100);
  });
}
