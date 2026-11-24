import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/video_display_mode.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_chrome_buttons.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_glass_panel.dart';
import 'package:onyx/screens/player/widgets/video_zoom_hint.dart';

/// L'indication du pincement — « Remplir la hauteur », « Original » — est une
/// capsule fine du verre du lecteur, pas un pavé à part. L'utilisateur la
/// trouvait trop grosse à côté de ce que le lecteur pose d'autre sur l'image.
void main() {
  Future<void> pumpHint(WidgetTester tester, {bool visible = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: VideoZoomHint(
              mode: VideoDisplayMode.fillHeight,
              visible: visible,
            ),
          ),
        ),
      );

  testWidgets('une capsule du verre du lecteur, plus basse qu’un bouton',
      (tester) async {
    await pumpHint(tester);

    final glass = find.byType(OnyxGlassPanel);
    expect(glass, findsOneWidget);
    expect(find.text(VideoDisplayMode.fillHeight.label), findsOneWidget);

    final size = tester.getSize(glass);
    expect(size.height, VideoZoomHint.height);
    // Fine : plus basse que le disque d'un bouton rond, qu'on touche, lui.
    expect(size.height, lessThan(OnyxIconButton.glassDisc));
    // Une capsule : des bouts ronds, pas un pavé aux coins de 12.
    expect(
      tester.widget<OnyxGlassPanel>(glass).radius,
      const BorderRadius.all(Radius.circular(VideoZoomHint.height / 2)),
    );
  });

  testWidgets('elle ne prend aucun toucher et s’efface', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
              ),
              const VideoZoomHint(
                mode: VideoDisplayMode.fill,
                visible: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OnyxGlassPanel), warnIfMissed: false);
    expect(taps, 1, reason: 'le pincement et le toucher passent dessous');

    await pumpHint(tester, visible: false);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
  });
}
