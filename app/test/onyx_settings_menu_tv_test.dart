import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/hooks/use_player_popup.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';
import 'package:onyx/screens/player/playback/sleep_timer.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_settings_menu.dart';
import 'package:onyx/screens/player/video_display_mode.dart';
import 'package:onyx/theme/focus_fill.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';

import 'support/tv_nav_harness.dart';

/// Le défaut que ce fichier verrouille : sur un téléviseur, le menu de réglages
/// du Chrome Onyx s'ouvrait, la télécommande y déplaçait bien le focus — mais
/// rien à l'écran ne le montrait. L'`InkWell` de chaque ligne faisait peindre
/// son halo par le [Material] du menu, c'est-à-dire *sous* le fond opaque du
/// panneau. Impossible, dès lors, de savoir où l'on est, donc impossible de
/// changer de langue : le menu passait pour bloqué.
///
/// Les tests tournent dans les deux systèmes de navigation (`TvNavHarness`),
/// le menu étant ouvert par un vrai [PlayerPopupHost], comme le lecteur.
void main() {
  const down = TraversalDirection.down;
  const up = TraversalDirection.up;
  const left = TraversalDirection.left;

  TvNavHarness.forEachEngine((engine) {
    testWidgets('la ligne où se trouve la télécommande se voit',
        (tester) async {
      await _pumpMenu(tester, engine);

      // Une seule, et c'est bien celle qui détient le focus : deux lignes
      // allumées, ou zéro, et l'écran ment sur ce que fera la touche OK.
      expect(_highlighted(tester), 'Audio');
    });

    testWidgets('les flèches parcourent le menu', (tester) async {
      final nav = await _pumpMenu(tester, engine);

      await nav.press(down);
      expect(_highlighted(tester), 'Sous-titres');

      await nav.press(up);
      expect(_highlighted(tester), 'Audio');
    });

    testWidgets(
        'OK ouvre la section et la télécommande arrive sur la piste en '
        'cours', (tester) async {
      final nav = await _pumpMenu(tester, engine);

      await nav.select();

      // Pas la première ligne de la liste : celle qui est déjà jouée. C'est de
      // là que l'utilisateur compte se déplacer.
      expect(_highlighted(tester), 'English');
    });

    testWidgets('retour remonte à l’index, sur la ligne d’où l’on vient',
        (tester) async {
      final nav = await _pumpMenu(tester, engine);
      await nav.select();

      // Gauche : le menu est une colonne, la touche n'y a rien d'autre à faire
      // et c'est le geste que le chevron du bandeau annonce.
      await nav.press(left);

      expect(find.text('Vitesse de lecture'), findsOneWidget);
      expect(_highlighted(tester), 'Audio');
    });

    testWidgets('OK sur une piste la choisit', (tester) async {
      final session = _FakeSession();
      final nav = await _pumpMenu(tester, engine, session: session);

      await nav.select();
      await nav.press(up);
      await nav.select();

      expect(session.chosen?.title, 'Français');
    });

    testWidgets('la minuterie de veille se règle à la télécommande',
        (tester) async {
      final nav = await _pumpMenu(tester, engine);

      // Audio, Sous-titres, Vitesse de lecture, Affichage, Minuterie de veille.
      for (var i = 0; i < 4; i++) {
        await nav.press(down);
      }
      expect(_highlighted(tester), 'Minuterie de veille');
      await nav.select();
      expect(_highlighted(tester), 'Désactivée');

      // Désactivée, 5, 10, 15, 30 minutes.
      for (var i = 0; i < 4; i++) {
        await nav.press(down);
      }
      await nav.select();

      expect(SleepTimer.instance.chosen, const Duration(minutes: 30));

      // Avant la fin du test : il refuse de se terminer sur une minuterie qui
      // court encore.
      SleepTimer.instance.resetForTest();
    });

    testWidgets('Retour remonte d’une section à l’index, puis ferme le menu',
        (tester) async {
      final nav = await _pumpMenu(tester, engine);
      await nav.select();
      expect(_highlighted(tester), 'English');

      // Premier Retour : la section remonte à l'index, le menu reste ouvert.
      await nav.back();
      expect(find.text('Vitesse de lecture'), findsOneWidget);
      expect(_highlighted(tester), 'Audio');

      // Second Retour : l'index ne remonte plus nulle part, le menu se ferme.
      await nav.back();
      expect(find.text('Vitesse de lecture'), findsNothing);
    });

    // Sur un téléviseur, chaque réglage a son bouton rond et son propre menu
    // (ADR-0130) : pas d'index à traverser pour changer une piste.
    group('le menu d’un seul réglage', () {
      testWidgets('s’ouvre sur le choix en cours, sous le nom du réglage',
          (tester) async {
        await _pumpMenu(tester, engine, standalone: OnyxMenuSection.audio);

        expect(_highlighted(tester), 'English');
        // L'en-tête nomme le réglage ; les lignes de l'index n'existent pas.
        expect(find.text('Audio'), findsOneWidget);
        expect(find.text('Vitesse de lecture'), findsNothing);
        expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      });

      testWidgets('Retour le ferme : il n’y a pas d’index où remonter',
          (tester) async {
        final nav =
            await _pumpMenu(tester, engine, standalone: OnyxMenuSection.audio);

        await nav.back();

        expect(find.text('English'), findsNothing);
        expect(find.text('Vitesse de lecture'), findsNothing);
      });

      testWidgets('Gauche n’y remonte nulle part', (tester) async {
        final nav =
            await _pumpMenu(tester, engine, standalone: OnyxMenuSection.audio);

        await nav.press(left);

        expect(_highlighted(tester), 'English');
        expect(find.text('Vitesse de lecture'), findsNothing);
      });

      testWidgets('OK sur un choix le prend et ferme le menu', (tester) async {
        final session = _FakeSession();
        final nav = await _pumpMenu(tester, engine,
            session: session, standalone: OnyxMenuSection.audio);

        await nav.press(up);
        await nav.select();

        expect(session.chosen?.title, 'Français');
        expect(find.text('English'), findsNothing);
      });

      testWidgets(
          'la minuterie sépare « Désactivée » de ses durées, et le filet ne '
          'prend pas la télécommande', (tester) async {
        final nav =
            await _pumpMenu(tester, engine, standalone: OnyxMenuSection.sleep);
        expect(_highlighted(tester), 'Désactivée');

        await nav.press(down);

        expect(_highlighted(tester), '5 minutes');
      });
    });

    if (engine == TvNavEngine.dpad) {
      testWidgets(
          'une touche Retour suivie de son popRoute ne défait qu’un '
          'niveau', (tester) async {
        final nav = await _pumpMenu(tester, engine);
        await nav.select();
        expect(_highlighted(tester), 'English');

        // Sur Apple TV, une même pression arrive deux fois : la touche, puis
        // `popRoute` (TvBack.claimKey les dédoublonne). Un seul niveau est
        // défait par paire.
        await nav.back();
        await nav.popRoute();
        expect(find.text('Vitesse de lecture'), findsOneWidget,
            reason: 'la section est remontée, le menu reste ouvert');
        expect(_highlighted(tester), 'Audio');

        await nav.back();
        await nav.popRoute();
        expect(find.text('Vitesse de lecture'), findsNothing,
            reason: 'la seconde paire ferme le menu');
      });
    }
  });
}

/// Le libellé de la ligne mise en évidence à l'écran — pas celle qui détient le
/// focus : ce qui est en cause ici est ce que l'utilisateur voit. Sur un
/// téléviseur, c'est la pastille blanche de `_OnyxMenuTile` ([FocusFill],
/// ADR-0112 et ADR-0130).
String _highlighted(WidgetTester tester) {
  final fill = find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == FocusFill.fill,
  );
  expect(fill, findsOneWidget);
  return tester
      .widget<Text>(
          find.descendant(of: fill, matching: find.byType(Text)).first)
      .data!;
}

/// L'écran d'accueil : il ouvre le menu par un vrai [PlayerPopupHost], après
/// sa première image, comme le lecteur ouvre un popup.
class _MenuHome extends StatefulWidget {
  const _MenuHome({
    required this.host,
    required this.session,
    this.standalone,
  });

  final PlayerPopupHost host;
  final _FakeSession session;

  /// Le réglage du menu seul, ou nul pour l'index.
  final OnyxMenuSection? standalone;

  @override
  State<_MenuHome> createState() => _MenuHomeState();
}

class _MenuHomeState extends State<_MenuHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.host.insert(
        context,
        (dismiss) => Material(
          type: MaterialType.transparency,
          child: MediaQuery(
            // La police de test est à chasse fixe et bien plus large que la
            // vraie : sans ça les libellés débordent du panneau.
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(0.4),
            ),
            child: OnyxSettingsMenu(
              session: widget.session,
              currentMode: VideoDisplayMode.original,
              onModeChanged: (_) {},
              playbackRate: 1.0,
              playbackRates: const [0.5, 1.0, 1.5, 2.0],
              onRateChanged: (_) {},
              initialSection: widget.standalone ?? OnyxMenuSection.root,
              standalone: widget.standalone != null,
              onClose: dismiss,
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

/// Monte le menu comme le lecteur le fait : dans un [PlayerPopupHost], sous
/// le système de navigation [engine].
Future<TvNavHarness> _pumpMenu(
  WidgetTester tester,
  TvNavEngine engine, {
  _FakeSession? session,
  OnyxMenuSection? standalone,
}) async {
  final host = PlayerPopupHost(isActive: () => true, onDismissed: (_) {});
  addTearDown(host.dispose);

  final nav = await TvNavHarness.pump(
    tester,
    _MenuHome(
      host: host,
      session: session ?? _FakeSession(),
      standalone: standalone,
    ),
    engine: engine,
  );
  await tester.pumpAndSettle();
  return nav;
}

class _FakeSession implements PlaybackSession {
  PlaybackTrack? chosen;

  @override
  List<PlaybackTrack> get audioTracks => const [
        PlaybackTrack(id: '1', title: 'Français', language: 'fra'),
        PlaybackTrack(id: '2', title: 'English', language: 'eng'),
      ];

  @override
  List<PlaybackTrack> get subtitleTracks => const [
        PlaybackTrack(id: 'no'),
        PlaybackTrack(id: '3', title: 'Français', language: 'fra'),
      ];

  /// Pas la première de la liste : c'est ce qui permet de distinguer « la piste
  /// en cours » de « la première ligne venue ».
  @override
  PlaybackTrack? get currentAudioTrack => audioTracks[1];

  @override
  PlaybackTrack? get currentSubtitleTrack => subtitleTracks.first;

  @override
  Future<void> setAudioTrack(PlaybackTrack track) async => chosen = track;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
