import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_motion.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/nav/tv_sections_scroll.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_entry.dart';
import 'package:onyx/tv/tv_key_repeat.dart';
import 'package:onyx/tv/tv_mode.dart';

/// Le défilement d'une fiche de téléviseur (`TvSectionsScroll`, ADR-0128) :
/// où la page se pose pour la ligne focalisée, et à quelle allure elle y va.
///
/// Avec les animations, contrairement au banc de navigation : c'est l'allure
/// qui est en cause ici. De « Lecture » à la distribution, la page traversait
/// plus d'un demi-écran en 200 ms.
void main() {
  setUp(() {
    TvMode.enabled.value = true;
    TvKeyRepeat.debugReset();
  });
  tearDown(() {
    TvMode.enabled.value = false;
    TvKeyRepeat.debugReset();
  });

  /// Une fiche réduite à l'essentiel, montée comme `main.dart` monte l'app
  /// avec l'ancien système : un en-tête et son action, puis des sections de
  /// [sectionHeight] pixels avec chacune un titre et [rows] lignes.
  Future<void> pumpPage(
    WidgetTester tester, {
    double headerHeight = 500,
    double sectionHeight = 700,
    int sections = 2,
    int rows = 1,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget button(String label, {bool autofocus = false}) => SizedBox(
          height: 60,
          child: TextButton(
            autofocus: autofocus,
            onPressed: () {},
            child: Text(label),
          ),
        );

    await tester.pumpWidget(
      TvScope(
        isTv: true,
        child: MaterialApp(
          shortcuts: <ShortcutActivator, Intent>{
            ...WidgetsApp.defaultShortcuts,
            ...tvSelectShortcuts,
          },
          actions: <Type, Action<Intent>>{
            ...WidgetsApp.defaultActions,
            DirectionalFocusIntent: TvDirectionalFocusAction(),
          },
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: FocusTraversalGroup(
              policy: TvTraversalPolicy(),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: TvRegion.sections(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TvRegion.section(
                      id: 'hero',
                      child: SizedBox(
                        height: headerHeight,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: button('Lecture', autofocus: true),
                        ),
                      ),
                    ),
                    for (var s = 1; s <= sections; s++)
                      TvRegion.section(
                        id: 'section-$s',
                        child: SizedBox(
                          height: sectionHeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Le titre de la section, que rien ne focalise.
                              const SizedBox(height: 80),
                              for (var r = 1; r <= rows; r++) ...[
                                button('S$s L$r'),
                                const SizedBox(height: 75),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  Future<void> down(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    // L'image qui pose le focus, puis celle qui lance le défilement.
    await tester.pump();
    await tester.pump();
  }

  String? focused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? text;
    void visit(Element element) {
      if (text != null) return;
      final widget = element.widget;
      if (widget is Text) {
        text = widget.data;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return text;
  }

  testWidgets(
      'd’une section à l’autre, la page prend la durée d’un changement de '
      'section et part en douceur', (tester) async {
    await pumpPage(tester);
    expect(focused(), 'Lecture');

    await down(tester);
    expect(focused(), 'S1 L1');
    // La section se cale à la marge du haut : 500 px d'en-tête au-dessus.
    const target = 500 - TvSectionsScroll.topMargin;

    // Au quart du temps, la page n'a pas fait le quart du chemin : un
    // ease-out en aurait déjà fait plus du tiers.
    await tester.pump(AppMotion.section * 0.25);
    expect(position(tester).pixels, greaterThan(0));
    expect(position(tester).pixels, lessThan(target * 0.25));

    // À la durée d'un pas ordinaire, elle est encore en route : c'est là
    // qu'elle arrivait d'un coup avant.
    await tester.pump(AppMotion.standard - AppMotion.section * 0.25);
    expect(position(tester).pixels, lessThan(target * 0.6));

    await tester.pump(AppMotion.section);
    expect(position(tester).pixels, moreOrLessEquals(target));
  });

  testWidgets(
      'dans une section, la ligne suivante ne fait rien défiler tant qu’elle '
      'tient à l’écran', (tester) async {
    await pumpPage(tester, rows: 3);
    await down(tester);
    await tester.pumpAndSettle();
    final rest = position(tester).pixels;

    await down(tester);
    expect(focused(), 'S1 L2');
    await tester.pumpAndSettle();
    expect(position(tester).pixels, rest);
  });

  testWidgets(
      'une ligne trop basse fait monter la page juste assez, à l’allure '
      'd’un pas', (tester) async {
    // Lignes à 80, 215, 350, 485 px du haut de la section : sous la marge du
    // haut, la quatrième finit à 581 px, plus bas que 72 % de 720.
    await pumpPage(tester, rows: 4, sectionHeight: 900);
    for (var i = 0; i < 3; i++) {
      await down(tester);
      await tester.pumpAndSettle();
    }
    final rest = position(tester).pixels;

    await down(tester);
    expect(focused(), 'S1 L4');
    await tester.pump(const Duration(milliseconds: 320));
    final moved = position(tester).pixels - rest;
    expect(moved, greaterThan(0));
    await tester.pumpAndSettle();
    expect(position(tester).pixels - rest, moreOrLessEquals(moved),
        reason: 'un petit trajet est fini bien avant la durée d’une section');

    final row = tester.getRect(find.widgetWithText(TextButton, 'S1 L4'));
    expect(
      row.bottom,
      moreOrLessEquals(720 * TvSectionsScroll.focusBottom, epsilon: 1),
    );
  });

  testWidgets('sous « réduire les animations », la page saute à sa place',
      (tester) async {
    await pumpPage(tester, reduceMotion: true);
    await down(tester);
    expect(
      position(tester).pixels,
      moreOrLessEquals(500 - TvSectionsScroll.topMargin),
    );
  });

  testWidgets('la durée suit la distance, entre un pas et une section',
      (tester) async {
    await pumpPage(tester);
    final context = tester.element(find.text('Lecture'));
    Duration at(double distance) => TvSectionsScroll.durationFor(
          context,
          distance: distance,
          viewportExtent: 720,
        );

    expect(at(0), AppMotion.standard);
    expect(at(135), greaterThan(AppMotion.standard));
    expect(at(135), lessThan(const Duration(milliseconds: 300)),
        reason: 'un épisode de plus dans une liste reste un pas');
    expect(at(720 * TvSectionsScroll.fullTravel), AppMotion.section);
    expect(at(2000), AppMotion.section,
        reason: 'jamais plus long qu’un changement de section');
  });

  testWidgets(
      'flèche maintenue : le défilement garde sa durée la plus courte, les '
      'pas se suivent', (tester) async {
    await pumpPage(tester);
    final context = tester.element(find.text('Lecture'));
    TvKeyRepeat.install();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    expect(TvKeyRepeat.isRepeating, isTrue);

    expect(
      TvSectionsScroll.durationFor(context, distance: 600, viewportExtent: 720),
      AppMotion.track,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  });
}
