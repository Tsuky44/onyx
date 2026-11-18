import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/screens/shell/mobile_top_bar.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/lite_mode.dart';
import 'package:onyx/widgets/global/account_menu.dart';
import 'package:onyx/widgets/global/backdrop_extension.dart';
import 'package:onyx/widgets/global/hero_banner.dart';
import 'package:onyx/widgets/global/liquid_glass.dart';
import 'package:onyx/widgets/global/onyx_mark.dart';
import 'package:onyx/widgets/global/onyx_wordmark.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La barre du haut du téléphone (ADR-0144) : la marque dans une pilule de
/// verre liquide et le compte dans un rond du même verre, sans bandeau ; au
/// défilement, le haut de la page se floute en fondu sous elles. L'affiche
/// de l'accueil garde son cadrage sous la barre et se prolonge au-dessus en
/// miroir flou.
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
      'au repos, la marque dans une pilule de verre, le compte dans un rond, '
      'et pas de bandeau', (tester) async {
    var home = 0;
    await _pump(tester, scrolled: false, onLogoTap: () => home++);

    final pill = find.byType(BrandPill);
    expect(
        find.descendant(of: pill, matching: find.byType(OnyxMark)), findsOne);
    expect(find.descendant(of: pill, matching: find.byType(OnyxWordmark)),
        findsOne);
    expect(find.descendant(of: pill, matching: find.byType(LiquidGlass)),
        findsOne);
    final account = find.byType(AccountMenu);
    expect(find.descendant(of: account, matching: find.byType(LiquidGlass)),
        findsOne);

    // Les deux pièces de verre ont la même hauteur, sous la barre d'état.
    final pillRect = tester.getRect(pill);
    final accountRect = tester.getRect(
        find.descendant(of: account, matching: find.byType(LiquidGlass)));
    expect(pillRect.height, AccountMenu.liquidSize);
    expect(accountRect.height, AccountMenu.liquidSize);
    expect(pillRect.top, greaterThanOrEqualTo(54));
    expect(accountRect.right, closeTo(_phone.width - 16, 0.5));

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

  Future<void> pumpExtension(WidgetTester tester,
      {required double extendTop, bool lite = false}) {
    return tester.pumpWidget(MaterialApp(
      home: LiteScope(
        isLite: lite,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 390,
            height: 464 + extendTop,
            child: BackdropExtension(
              extendTop: extendTop,
              image: () => const ColoredBox(
                  key: ValueKey('image'), color: Color(0xFF884422)),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets(
      'l’image nette garde son cadrage sous la barre, prolongée au-dessus '
      'en miroir flou', (tester) async {
    await pumpExtension(tester, extendTop: 110);
    final sharp = find.descendant(
        of: find.byType(ShaderMask),
        matching: find.byKey(const ValueKey('image')));
    expect(tester.getRect(sharp).top, 110);
    expect(tester.getRect(sharp).height, 464);

    final extension = find.byKey(const ValueKey('backdrop-extension'));
    expect(tester.getRect(extension).height, 110 + BackdropExtension.blend);
    expect(find.descendant(of: extension, matching: find.byType(ImageFiltered)),
        findsOne);
    // Le miroir au-dessus de la ligne, l'image elle-même dessous.
    expect(
        find.descendant(
            of: extension, matching: find.byKey(const ValueKey('image'))),
        findsNWidgets(2));
  });

  testWidgets('sans flou, pas de miroir : un voile sombre', (tester) async {
    await pumpExtension(tester, extendTop: 110, lite: true);
    expect(find.byKey(const ValueKey('backdrop-extension')), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byKey(const ValueKey('image')), findsOne);
  });

  testWidgets('sans prolongement, l’image seule', (tester) async {
    await pumpExtension(tester, extendTop: 0);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey('image'))).top, 0);
  });
}
