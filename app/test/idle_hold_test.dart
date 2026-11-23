import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/utils/idle_hold.dart';

// Le moteur du lecteur ne reste pas en mémoire au-delà de son délai
// (PlayerEnginePool, ADR-0166). La règle est tenue par IdleHold.
void main() {
  testWidgets('une ressource que personne ne reprend est libérée au délai',
      (tester) async {
    final discarded = <String>[];
    final hold = IdleHold<String>(
      limit: const Duration(minutes: 2),
      discard: discarded.add,
    );

    hold.put('moteur');
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(discarded, isEmpty);
    expect(hold.isHolding, isTrue);

    await tester.pump(const Duration(seconds: 2));
    expect(discarded, ['moteur']);
    expect(hold.isHolding, isFalse);
    expect(hold.take(), isNull);
  });

  testWidgets('une ressource reprise à temps n\'est jamais libérée',
      (tester) async {
    final discarded = <String>[];
    final hold = IdleHold<String>(
      limit: const Duration(minutes: 2),
      discard: discarded.add,
    );

    hold.put('moteur');
    await tester.pump(const Duration(minutes: 1));
    expect(hold.take(), 'moteur');
    await tester.pump(const Duration(minutes: 10));
    expect(discarded, isEmpty);
  });

  testWidgets('reposer une ressource relance le délai', (tester) async {
    final discarded = <String>[];
    final hold = IdleHold<String>(
      limit: const Duration(minutes: 2),
      discard: discarded.add,
    );

    hold.put('moteur');
    await tester.pump(const Duration(minutes: 1, seconds: 30));
    hold.put(hold.take()!);
    await tester.pump(const Duration(minutes: 1, seconds: 30));
    expect(discarded, isEmpty);
    await tester.pump(const Duration(seconds: 31));
    expect(discarded, ['moteur']);
  });
}
