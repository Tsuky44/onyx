import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/widgets/desktop_pip_overlay.dart';

void main() {
  Widget host({
    required VoidCallback onToggle,
    required VoidCallback onRestore,
    ValueChanged<int>? onSeek,
    bool playing = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 270,
          child: DesktopPipOverlay(
            playing: playing,
            onTogglePlayback: onToggle,
            onSeek: onSeek ?? (_) {},
            onRestore: onRestore,
            onDrag: null,
          ),
        ),
      ),
    );
  }

  testWidgets('le bouton du coin rend la fenêtre à sa taille normale',
      (tester) async {
    var restored = 0;
    var toggled = 0;
    await tester.pumpWidget(host(
      onToggle: () => toggled++,
      onRestore: () => restored++,
    ));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(240, 135));
    addTearDown(mouse.removePointer);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('pip-restore')));
    expect(restored, 1);
    expect(toggled, 0);
  });

  testWidgets('un clic sur l’image met en pause ou relance', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(host(onToggle: () => toggled++, onRestore: () {}));

    await tester.tapAt(const Offset(240, 135));
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggled, 1);
  });

  testWidgets('un double-clic revient à la fenêtre normale', (tester) async {
    var restored = 0;
    await tester.pumpWidget(host(onToggle: () {}, onRestore: () => restored++));

    await tester.tapAt(const Offset(240, 135));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(240, 135));
    await tester.pump(const Duration(milliseconds: 400));
    expect(restored, 1);
  });

  testWidgets('au survol, reculer et avancer sautent de dix secondes',
      (tester) async {
    final jumps = <int>[];
    await tester.pumpWidget(host(
      onToggle: () {},
      onRestore: () {},
      onSeek: jumps.add,
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(240, 135));
    addTearDown(mouse.removePointer);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('pip-rewind')));
    await tester.tap(find.byKey(const ValueKey('pip-forward')));
    expect(jumps, [-10, 10]);
  });

  testWidgets('au survol, le bouton du centre met en pause sans double appel',
      (tester) async {
    var toggled = 0;
    await tester.pumpWidget(host(onToggle: () => toggled++, onRestore: () {}));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(240, 135));
    addTearDown(mouse.removePointer);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('pip-play-pause')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggled, 1);
  });

  testWidgets('sans survol, les boutons ne prennent aucun clic',
      (tester) async {
    final jumps = <int>[];
    await tester.pumpWidget(host(
      onToggle: () {},
      onRestore: () {},
      onSeek: jumps.add,
    ));
    await tester.tap(find.byKey(const ValueKey('pip-forward')),
        warnIfMissed: false);
    expect(jumps, isEmpty);
  });
}
