import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/hooks/use_pause_info.dart';

/// L'écran « Vous regardez » monte après cinq secondes de pause sans geste ;
/// un geste le retire et relance les cinq secondes (ADR-0137).
void main() {
  testWidgets('monte cinq secondes après une pause laissée telle quelle',
      (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    watch.notePaused();
    await tester.pump(const Duration(milliseconds: 4900));
    expect(watch.visible, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(watch.visible, isTrue);
    watch.dispose();
  });

  testWidgets('le geste qui met pause ne compte pas comme une activité',
      (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    // Le clic met pause puis réveille le chrome dans le même appel.
    watch.notePaused();
    watch.noteActivity();
    await tester.pump(PauseInfoWatch.defaultDelay);
    expect(watch.visible, isTrue);
    watch.dispose();
  });

  testWidgets('un geste pendant l’attente relance les cinq secondes',
      (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    watch.notePaused();
    await tester.pump(const Duration(seconds: 4));
    // La souris bouge : quelqu'un est là, l'attente repart de zéro.
    watch.noteActivity();
    await tester.pump(const Duration(seconds: 4));
    expect(watch.visible, isFalse);
    // La souris s'est arrêtée : cinq secondes plus tard, l'écran monte.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(watch.visible, isTrue);
    watch.dispose();
  });

  testWidgets('retiré par la souris, il revient quand elle s’arrête',
      (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    watch.notePaused();
    await tester.pump(PauseInfoWatch.defaultDelay);
    expect(watch.visible, isTrue);
    watch.noteActivity();
    expect(watch.visible, isFalse);
    await tester.pump(PauseInfoWatch.defaultDelay);
    expect(watch.visible, isTrue);
    watch.dispose();
  });

  testWidgets('attend qu’un menu se ferme, puis cinq secondes de calme',
      (tester) async {
    var menuOpen = true;
    final watch = PauseInfoWatch(mayShow: () => !menuOpen);
    watch.notePaused();
    await tester.pump(const Duration(seconds: 30));
    expect(watch.visible, isFalse);
    // Le menu se ferme d'un geste, qui relance l'attente.
    menuOpen = false;
    watch.noteActivity();
    await tester.pump(const Duration(seconds: 4));
    expect(watch.visible, isFalse);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(watch.visible, isTrue);
    watch.dispose();
  });

  testWidgets('hors pause, un geste ne fait rien monter', (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    watch.noteActivity();
    await tester.pump(const Duration(seconds: 30));
    expect(watch.visible, isFalse);
    watch.dispose();
  });

  testWidgets('un geste ferme l’écran affiché et dit qu’il l’a fermé',
      (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    var notified = 0;
    watch.addListener(() => notified++);
    watch.notePaused();
    await tester.pump(PauseInfoWatch.defaultDelay);
    expect(watch.noteActivity(), isTrue);
    expect(watch.visible, isFalse);
    expect(watch.noteActivity(), isFalse);
    expect(notified, 2);
    watch.dispose();
  });

  testWidgets('la reprise de la lecture annule l’attente', (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    watch.notePaused();
    await tester.pump(const Duration(seconds: 1));
    watch.noteResumed();
    await tester.pump(const Duration(seconds: 30));
    expect(watch.visible, isFalse);
    watch.dispose();
  });

  testWidgets('une nouvelle pause relance le compte à rebours', (tester) async {
    final watch = PauseInfoWatch(mayShow: () => true);
    watch.notePaused();
    await tester.pump(const Duration(seconds: 1));
    watch.noteActivity();
    watch.noteResumed();
    watch.notePaused();
    await tester.pump(PauseInfoWatch.defaultDelay);
    expect(watch.visible, isTrue);
    watch.dispose();
  });
}
