import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/screens/shell/mobile_top_bar.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/account_menu.dart';
import 'package:onyx/widgets/global/hero_top_fade.dart';
import 'package:onyx/widgets/global/hero_banner.dart';
import 'package:onyx/widgets/global/liquid_glass.dart';
import 'package:onyx/widgets/global/onyx_mark.dart';
import 'package:onyx/widgets/global/onyx_wordmark.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La barre du haut du téléphone (ADR-0144) : la marque et le compte posés
/// sans verre, sans bandeau ; au défilement, le haut de la page se floute en
/// fondu sous eux. L'affiche de l'accueil garde son cadrage sous la barre et
/// se fond dans le noir par le haut.
class _FakeApiClient extends ApiClient {
  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Future<MediaDetails> getMediaDetails(int id) async =>
      throw UnimplementedError();
}

const _phone = Size(390, 844);

Future<void> _pump(
  WidgetTester tester, {
  required bool scrolled,
  VoidCallback? onLogoTap,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _phone * 3;
  tester.view.padding = const FakeViewPadding(top: 54 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final api = _FakeApiClient();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: MobileTopBar(
                    scrolled: scrolled,
                    authProvider: context.read<AuthProvider>(),
                    homeProvider: context.read<HomeProvider>(),
                    onLogoTap: onLogoTap ?? () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _edgeOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const ValueKey('mobile-top-bar-edge')))
    .opacity;

void main() {
  testWidgets(
      'au repos, la marque et le compte posés sans verre, et pas de bandeau',
      (tester) async {
    var home = 0;
    await _pump(tester, scrolled: false, onLogoTap: () => home++);

    final pill = find.byType(BrandPill);
    expect(
        find.descendant(of: pill, matching: find.byType(OnyxMark)), findsOne);
    expect(find.descendant(of: pill, matching: find.byType(OnyxWordmark)),
        findsOne);
    expect(find.byType(LiquidGlass), findsNothing,
        reason: 'un verre transparent laissait voir l’affiche à travers');
    final disc = find.byKey(const ValueKey('account-plain-disc'));
    expect(tester.getSize(disc).width, AccountMenu.plainSize);

    // Des cibles de 44 points, sous la barre d'état.
    final pillRect = tester.getRect(pill);
    final account = tester.getRect(find.byType(AccountMenu));
    expect(pillRect.height, AccountMenu.plainTarget);
    expect(account.height, AccountMenu.plainTarget);
    expect(pillRect.top, greaterThanOrEqualTo(54));
    expect(account.right, closeTo(_phone.width - 16, 0.5));

    expect(_edgeOpacity(tester), 0, reason: 'pas de bandeau en haut de page');

    await tester.tap(pill);
    expect(home, 1);
  });

  testWidgets('au défilement, le haut de la page se floute sous la barre',
      (tester) async {
    await _pump(tester, scrolled: true);
    expect(_edgeOpacity(tester), 1);
    final edge = tester.getRect(find.byType(ScrollEdgeBlur));
    // Le fondu descend sous la rangée de verre avant de s'éteindre.
    expect(edge.bottom, 54 + MobileTopBar.rowHeight + MobileTopBar.fadeBelow);
  });

  testWidgets('le bandeau grandit de ce qu’il passe sous la barre',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = _phone * 3;
    addTearDown(tester.view.reset);
    final api = _FakeApiClient();
    double? natural;
    await tester.pumpWidget(Provider<ApiClient>.value(
      value: api,
      child: MaterialApp(
        home: Builder(builder: (context) {
          natural = HeroBanner.heightFor(context);
          return SingleChildScrollView(
            child: HeroBanner(
              media: Media.fromJson({
                'id': 1,
                'type': 'movie',
                'title': 'Dune',
                'duration': 6000
              }),
              onPlay: () {},
              extendTop: 110,
            ),
          );
        }),
      ),
    ));
    await tester.pump();
    expect(tester.getSize(find.byType(HeroBanner)).height, natural! + 110);
  });

  Future<void> pumpFade(WidgetTester tester, {required double top}) {
    return tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 390,
          height: 464 + top,
          child: HeroTopFade(
            top: top,
            image: const ColoredBox(
                key: ValueKey('image'), color: Color(0xFF884422)),
          ),
        ),
      ),
    ));
  }

  testWidgets(
      'l’image garde sa taille, un peu plus bas, et sort du noir par le haut',
      (tester) async {
    await pumpFade(tester, top: 110);
    final image = find.byKey(const ValueKey('image'));
    expect(tester.getRect(image).top, 110 + HeroTopFade.shift);
    expect(tester.getRect(image).height, 464,
        reason: 'la même taille, donc le même cadrage');
    expect(
        find.ancestor(of: image, matching: find.byType(ShaderMask)), findsOne);
    // Ni miroir ni flou : un flou sur l'arête brouillait les visages.
    expect(image, findsOne);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('sans barre au-dessus, l’image seule', (tester) async {
    await pumpFade(tester, top: 0);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey('image'))).top, 0);
  });

  test('le shader du flou se charge, ses réglages après la taille', () async {
    final program =
        await ui.FragmentProgram.fromAsset('shaders/scroll_edge_blur.frag');
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);
    // 0 et 1 : la taille, posée par le moteur ; puis hauteur, flou, axe.
    for (var i = 2; i <= 5; i++) {
      shader.setFloat(i, 1);
    }
    expect(() => shader.setFloat(6, 1), throwsA(anything));
  });

  testWidgets('hors Impeller, le flou se replie sur ses bandes',
      (tester) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isFalse,
        reason: 'le moteur des tests n’est pas Impeller');
    await _pump(tester, scrolled: true);
    expect(find.byKey(const ValueKey('scroll-edge-progressive')), findsNothing);
    expect(
      find.descendant(
          of: find.byType(ScrollEdgeBlur),
          matching: find.byType(BackdropFilter)),
      findsNWidgets(ScrollEdgeBlur.bands.length),
    );
  });

  test('le voile décroît sans coude et s’éteint en bas', () {
    for (final blurs in [true, false]) {
      var previous = ScrollEdgeBlur.veilAt(0, blurs: blurs);
      var previousStep = 0.0;
      for (var i = 1; i <= 100; i++) {
        final alpha = ScrollEdgeBlur.veilAt(i / 100, blurs: blurs);
        expect(alpha, lessThanOrEqualTo(previous));
        final step = previous - alpha;
        // Pas de saut d'une marche à la suivante : la pente varie peu.
        expect((step - previousStep).abs(), lessThan(0.006));
        previous = alpha;
        previousStep = step;
      }
      expect(ScrollEdgeBlur.veilAt(1, blurs: blurs), 0);
    }
  });
}
