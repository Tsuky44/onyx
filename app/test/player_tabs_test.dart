import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/watch_party.dart';
import 'package:onyx/screens/player/hooks/use_episodes_panel.dart';
import 'package:onyx/screens/player/hooks/use_player_tabs.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_tabs.dart';
import 'package:onyx/screens/player/widgets/player_tab_sheet.dart';
import 'package:onyx/screens/player/widgets/tabs/player_chapters_tab.dart';
import 'package:onyx/screens/player/widgets/tabs/player_info_tab.dart';
import 'package:onyx/screens/player/widgets/tabs/player_watch_party_tab.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/focus_fill.dart';
import 'package:provider/provider.dart';

import 'support/tv_nav_harness.dart';

/// Les onglets du lecteur et leurs contenus (ADR-0130) : ce que chacun montre,
/// ce que la télécommande y trouve, et la feuille qui les porte hors
/// téléviseur.
void main() {
  Media movie({String? overview}) => Media(
        id: 1,
        type: MediaType.movie,
        title: 'Le Phare',
        duration: 7200,
        overview: overview,
        isAvailable: true,
        createdAt: DateTime(2026),
      );

  Widget host(Widget child, {double height = 238}) => Provider<ApiClient>.value(
        value: ApiClient(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(height: height, child: child),
          ),
        ),
      );

  group('l’onglet Infos', () {
    testWidgets('le titre, sa ligne et le résumé', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerInfoTab(
          media: movie(),
          title: 'Le Phare',
          meta: '2019 · 2h 0min',
          overview: 'Deux gardiens, une île, une tempête.',
        )),
      ));

      expect(find.text('Le Phare'), findsOneWidget);
      expect(find.text('2019 · 2h 0min'), findsOneWidget);
      expect(find.text('Deux gardiens, une île, une tempête.'), findsOneWidget);
      // Un film n'a pas d'épisode voisin : rien à activer.
      expect(find.text('Épisode suivant'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans résumé, l’onglet le dit au lieu de rester vide',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerInfoTab(media: movie(), title: 'Le Phare')),
      ));

      expect(find.text('Aucun résumé disponible.'), findsOneWidget);
    });

    testWidgets('un épisode propose son voisin', (tester) async {
      var previous = 0;
      var next = 0;
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerInfoTab(
          media: movie(),
          title: 'Le Gardien',
          onPrevious: () => previous++,
          onNext: () => next++,
        )),
      ));

      await tester.tap(find.text('Épisode précédent'));
      await tester.tap(find.text('Épisode suivant'));
      expect((previous, next), (1, 1));
    });

    testWidgets('un résumé très long est coupé, pas débordé', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerInfoTab(
          media: movie(),
          title: 'Le Phare',
          overview: 'Une phrase qui se répète. ' * 80,
          onNext: () {},
        )),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Épisode suivant'), findsOneWidget);
    });
  });

  group('l’onglet Chapitres', () {
    final chapters = [
      VideoChapter(id: 1, startTime: 0, endTime: 292, title: 'Ouverture'),
      VideoChapter(id: 2, startTime: 292, endTime: 778, title: 'L’arrivée'),
      VideoChapter(id: 3, startTime: 778, endTime: 1490, title: ''),
    ];

    testWidgets('une carte par chapitre, celui qu’on regarde marqué',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerChaptersTab(
          chapters: chapters,
          positionSeconds: 300,
          onSeek: (_) {},
        )),
      ));

      expect(find.text('1 · Ouverture'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('2 · L’arrivée'), findsOneWidget);
      expect(find.text('04:52 · En cours'), findsOneWidget);
      // Un chapitre sans nom porte son numéro.
      expect(find.text('3 · Chapitre 3'), findsOneWidget);
    });

    testWidgets('un tap saute au début du chapitre', (tester) async {
      final seeks = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerChaptersTab(
          chapters: chapters,
          positionSeconds: 0,
          onSeek: seeks.add,
        )),
      ));

      await tester.tap(find.text('3 · Chapitre 3'));
      expect(seeks, [778]);
    });

    TvNavHarness.forEachEngine((engine) {
      testWidgets(
          'sur un téléviseur, la carte focalisée est blanche et OK y saute',
          (tester) async {
        final seeks = <int>[];
        final nav = await TvNavHarness.pump(
          tester,
          host(PlayerChaptersTab(
            chapters: chapters,
            positionSeconds: 300,
            onSeek: seeks.add,
          )),
          engine: engine,
        );
        await tester.pumpAndSettle();

        // La carte du chapitre en cours : c'est là que la rangée fait entrer.
        nodeLabelled('player-chapter-1').requestFocus();
        await TvNavHarness.settle(tester);
        await tester.pumpAndSettle();

        final lit = find.byWidgetPredicate((widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == FocusFill.fill);
        expect(lit, findsOneWidget);
        expect(
          find.descendant(of: lit, matching: find.text('2 · L’arrivée')),
          findsOneWidget,
        );

        await nav.press(TraversalDirection.right);
        await nav.select();
        expect(seeks, [778]);
      });

      testWidgets(
          'le chapitre en cours change pendant qu’on regarde la liste : la '
          'carte que la télécommande tient la garde', (tester) async {
        var position = 300;
        late StateSetter rebuild;
        await TvNavHarness.pump(
          tester,
          StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return host(PlayerChaptersTab(
              chapters: chapters,
              positionSeconds: position,
              onSeek: (_) {},
            ));
          }),
          engine: engine,
        );
        await tester.pumpAndSettle();
        nodeLabelled('player-chapter-2').requestFocus();
        await TvNavHarness.settle(tester);

        // La lecture entre dans le troisième chapitre, celui qui est focalisé.
        rebuild(() => position = 800);
        await tester.pumpAndSettle();

        expect(nodeLabelled('player-chapter-2').hasPrimaryFocus, isTrue);
        expect(find.text('12:58 · En cours'), findsOneWidget);
      });
    });
  });

  group('l’onglet Regarder ensemble', () {
    testWidgets('hors séance, il explique et propose de démarrer',
        (tester) async {
      var started = 0;
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerWatchPartyTab(
          code: null,
          members: const [],
          onStart: () async => started++,
          onLeave: () {},
        )),
      ));

      expect(find.text('Regardez à plusieurs'), findsOneWidget);
      expect(find.text('Partagez le code'), findsOneWidget);
      await tester.tap(find.text('Démarrer une séance'));
      await tester.pumpAndSettle();
      expect(started, 1);
    });

    testWidgets('un démarrage qui échoue le dit, et se retente',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerWatchPartyTab(
          code: null,
          members: const [],
          onStart: () async => throw StateError('refusé'),
          onLeave: () {},
        )),
      ));

      await tester.tap(find.text('Démarrer une séance'));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de démarrer la séance. Réessayez.'),
          findsOneWidget);
      expect(find.text('Démarrer une séance'), findsOneWidget);
    });

    testWidgets('en séance : le code, les participants, quitter',
        (tester) async {
      var left = 0;
      await tester.pumpWidget(MaterialApp(
        home: host(PlayerWatchPartyTab(
          code: 'K7QD',
          members: const [
            WatchPartyMember(username: 'alex', isHost: true, isYou: true),
            WatchPartyMember(username: '', device: 'iPhone'),
          ],
          onStart: () async {},
          onLeave: () => left++,
        )),
      ));

      expect(find.text('K7QD'), findsOneWidget);
      expect(find.text('2 participants'), findsOneWidget);
      expect(find.text('alex (vous)'), findsOneWidget);
      expect(find.text('Hôte'), findsOneWidget);
      // Un participant sans nom est un invité, sur son appareil.
      expect(find.text('Invité'), findsOneWidget);
      expect(find.text('iPhone'), findsOneWidget);
      // Hors téléviseur, le code se copie.
      expect(find.text('Copier'), findsOneWidget);

      await tester.tap(find.text('Quitter la séance'));
      expect(left, 1);
    });

    TvNavHarness.forEachEngine((engine) {
      testWidgets('sur un téléviseur, pas de « Copier »', (tester) async {
        await TvNavHarness.pump(
          tester,
          host(PlayerWatchPartyTab(
            code: 'K7QD',
            members: const [WatchPartyMember(username: 'alex', isYou: true)],
            onStart: () async {},
            onLeave: () {},
          )),
          engine: engine,
        );
        await tester.pumpAndSettle();

        expect(find.text('Copier'), findsNothing);
        expect(find.text('Quitter la séance'), findsOneWidget);
        expect(
            find.text('En attente des autres participants…'), findsOneWidget);
      });

      testWidgets(
          'sur un téléviseur, démarrer la séance laisse la télécommande sur '
          'le bouton de l’onglet, devenu « Quitter la séance »',
          (tester) async {
        String? code;
        late StateSetter rebuild;
        final nav = await TvNavHarness.pump(
          tester,
          StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return host(PlayerWatchPartyTab(
              code: code,
              members: const [],
              onStart: () async => rebuild(() => code = 'K7QD'),
              onLeave: () => rebuild(() => code = null),
            ));
          }),
          engine: engine,
        );
        await tester.pumpAndSettle();
        nodeLabelled('player-party-action').requestFocus();
        await TvNavHarness.settle(tester);

        await nav.select();
        await tester.pumpAndSettle();

        expect(find.text('K7QD'), findsOneWidget);
        expect(focusedLabelOf(primaryFocus), 'Quitter la séance',
            reason: 'le bouton pressé a disparu : la télécommande ne doit '
                'pas se retrouver nulle part');

        // Et dans l'autre sens.
        await nav.select();
        await tester.pumpAndSettle();
        expect(find.text('K7QD'), findsNothing);
        expect(focusedLabelOf(primaryFocus), 'Démarrer une séance');
      });
    });
  });

  group('la feuille des onglets, hors téléviseur', () {
    OnyxTabEntry entry(OnyxTab tab, String label) => OnyxTabEntry(
          tab: tab,
          label: label,
          builder: (_) => Text('contenu $label'),
        );

    Future<List<OnyxTab?>> pumpSheet(WidgetTester tester, Size size) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final changes = <OnyxTab?>[];
      OnyxTab? open = OnyxTab.info;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: StatefulBuilder(
            builder: (context, setState) => Stack(
              children: [
                if (open != null)
                  PlayerTabSheet(
                    tabs: [
                      entry(OnyxTab.info, 'Infos'),
                      entry(OnyxTab.chapters, 'Chapitres'),
                      entry(OnyxTab.stats, 'Stats'),
                    ],
                    open: open!,
                    onChanged: (tab) {
                      changes.add(tab);
                      setState(() => open = tab);
                    },
                  ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return changes;
    }

    testWidgets('ses onglets en tête, le contenu de celui qui est ouvert',
        (tester) async {
      final changes = await pumpSheet(tester, const Size(1280, 800));

      expect(find.text('contenu Infos'), findsOneWidget);
      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      expect(find.text('contenu Stats'), findsOneWidget);
      expect(find.text('contenu Infos'), findsNothing);
      expect(changes, [OnyxTab.stats]);
    });

    testWidgets('la croix et un tap à côté la ferment', (tester) async {
      var changes = await pumpSheet(tester, const Size(1280, 800));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(changes, [null]);
      expect(find.text('contenu Infos'), findsNothing);

      changes = await pumpSheet(tester, const Size(1280, 800));
      // Dans l'image, au-dessus de la feuille.
      await tester.tapAt(const Offset(640, 80));
      await tester.pumpAndSettle();
      expect(changes, [null]);
    });

    testWidgets('elle tient sur un téléphone tenu en largeur', (tester) async {
      await pumpSheet(tester, const Size(740, 360));

      expect(tester.takeException(), isNull);
      final sheet = tester.getRect(find.text('contenu Infos'));
      expect(sheet.top, greaterThan(0));
      expect(sheet.bottom, lessThanOrEqualTo(360));
    });
  });

  group('l’onglet ouvert', () {
    test('la liste des épisodes suit son onglet, et le chrome est prévenu',
        () async {
      final episodes = EpisodesPanelController(
        api: () => null,
        currentSeasonId: 3,
        currentShowId: 7,
        currentEpisodeId: 12,
      );
      addTearDown(episodes.dispose);
      final opened = <bool>[];
      final tabs = PlayerTabsController(
        episodes: episodes,
        showTitle: () => 'Ma série',
        onOpenChanged: opened.add,
      );
      addTearDown(tabs.dispose);
      var notified = 0;
      tabs.addListener(() => notified++);

      tabs.show(OnyxTab.info);
      expect(tabs.open, OnyxTab.info);
      expect(episodes.isOpen, isFalse);
      expect(opened, [true]);

      // Changer d'onglet ne rouvre pas le volet : il l'est déjà.
      tabs.show(OnyxTab.episodes);
      await Future<void>.delayed(Duration.zero);
      expect(episodes.isOpen, isTrue);
      expect(episodes.showTitle, 'Ma série');
      expect(opened, [true]);

      tabs.show(OnyxTab.stats);
      expect(episodes.isOpen, isFalse);

      // Le même onglet deux fois ne prévient personne.
      final before = notified;
      tabs.show(OnyxTab.stats);
      expect(notified, before);

      expect(tabs.close(), isTrue);
      expect(tabs.isOpen, isFalse);
      expect(opened, [true, false]);
      expect(tabs.close(), isFalse, reason: 'Retour continue vers le chrome');
    });
  });
}
