import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/tv_semantics_scroll_guard.dart';

SemanticsActionEvent _event(SemanticsAction type) =>
    SemanticsActionEvent(type: type, viewId: 0, nodeId: 1);

void main() {
  testWidgets(
      'sans VoiceOver, le pont d’accessibilité ne fait plus défiler les pages',
      (tester) async {
    final features = tester.platformDispatcher.accessibilityFeatures;

    expect(
      TvSemanticsScrollGuard.shouldDrop(
          _event(SemanticsAction.scrollToOffset), features),
      isTrue,
    );
  });

  testWidgets('les autres actions passent', (tester) async {
    final features = tester.platformDispatcher.accessibilityFeatures;

    expect(
      TvSemanticsScrollGuard.shouldDrop(_event(SemanticsAction.tap), features),
      isFalse,
    );
    expect(
      TvSemanticsScrollGuard.shouldDrop(
          _event(SemanticsAction.scrollUp), features),
      isFalse,
    );
  });

  testWidgets('avec VoiceOver, le défilement par l’accessibilité reste permis',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    expect(
      TvSemanticsScrollGuard.shouldDrop(
        _event(SemanticsAction.scrollToOffset),
        tester.platformDispatcher.accessibilityFeatures,
      ),
      isFalse,
    );
  });
}
