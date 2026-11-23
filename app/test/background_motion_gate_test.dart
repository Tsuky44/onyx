import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/services/background_memory_trim.dart';
import 'package:onyx/services/player_presence.dart';
import 'package:onyx/utils/on_screen.dart';
import 'package:onyx/widgets/global/background_motion_gate.dart';
import 'package:onyx/widgets/global/skeleton.dart';

Widget _app({bool desktop = true}) => MaterialApp(
      home: BackgroundMotionGate(
        desktop: desktop,
        child: const SkeletonPulse(child: SizedBox(width: 20, height: 20)),
      ),
    );

void main() {
  tearDown(() {
    AppForeground.debugSetFocused(true);
    AppForeground.debugSetVisible(true);
    BackgroundMemoryTrim.debugReset();
  });

  testWidgets('sur bureau, sans le focus, plus aucune animation ne tourne',
      (tester) async {
    await tester.pumpWidget(_app());
    expect(tester.hasRunningAnimations, isTrue);

    AppForeground.debugSetFocused(false);
    await tester.pump();
    await tester.pump();
    // Une animation encore active ferait échouer pumpAndSettle (timeout).
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    AppForeground.debugSetFocused(true);
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('un lecteur ouvert garde le mouvement, même sans le focus',
      (tester) async {
    await tester.pumpWidget(_app());
    PlayerPresence.enter();
    addTearDown(PlayerPresence.leave);

    AppForeground.debugSetFocused(false);
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('hors bureau, perdre le focus ne fige rien', (tester) async {
    await tester.pumpWidget(_app(desktop: false));
    AppForeground.debugSetFocused(false);
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('les images décodées sont rendues après le délai de grâce caché',
      (tester) async {
    var trimmed = 0;
    BackgroundMemoryTrim.attach(
      after: const Duration(seconds: 45),
      onTrim: () => trimmed++,
    );

    AppForeground.debugSetVisible(false);
    await tester.pump(const Duration(seconds: 44));
    expect(trimmed, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(trimmed, 1);
  });

  testWidgets('un retour avant le délai de grâce ne vide rien', (tester) async {
    var trimmed = 0;
    BackgroundMemoryTrim.attach(
      after: const Duration(seconds: 45),
      onTrim: () => trimmed++,
    );

    AppForeground.debugSetVisible(false);
    await tester.pump(const Duration(seconds: 20));
    AppForeground.debugSetVisible(true);
    await tester.pump(const Duration(minutes: 5));
    expect(trimmed, 0);
  });
}
