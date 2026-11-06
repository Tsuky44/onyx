import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/requests/widgets/request_moderation_dialogs.dart';
import 'package:onyx/screens/settings/widgets/settings_ui.dart';
import 'package:onyx/tv/nav/tv_back.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/widgets/global/detail_synopsis.dart';
import 'package:onyx/widgets/global/otp_code_dialog.dart';
import 'package:onyx/widgets/global/watch_list_editor_dialog.dart';

import 'support/tv_nav_harness.dart';

/// Dialogues, feuilles et menus sous dpad (ADR-0110, phase 5) : le focus y
/// entre, n'en sort pas aux flèches, et revient à l'élément d'origine quand
/// Retour les ferme, par la touche comme par `popRoute`.
///
/// Sur téléviseur, la coquille n'a pas de navigateur imbriqué : feuilles et
/// menus, qui prennent le navigateur le plus proche, vont donc au navigateur
/// racine comme les dialogues. L'inventaire de la phase 5 ne trouve qu'une
/// fenêtre qui ne soit pas une route, les menus du lecteur
/// (`PlayerPopupHost`), migrés en phase 7. Chaque mécanisme de l'app a sa
/// ligne, plus les dialogues partagés qui se montent sans fournisseur.

typedef _Opener = void Function(BuildContext context);

/// Une fenêtre de l'app ou un mécanisme, ouvert depuis l'élément d'origine.
typedef _Modal = ({String name, _Opener open});

List<_Modal> _modals() => [
      (
        name: 'showDialog (AlertDialog, boutons Material)',
        open: (context) => showDialog<void>(
              context: context,
              builder: (dialog) => AlertDialog(
                content: const Text('Corps'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Annuler')),
                  TextButton(onPressed: () {}, child: const Text('Valider')),
                ],
              ),
            ),
      ),
      (
        name: 'showModalBottomSheet (feuille)',
        open: (context) => showModalBottomSheet<void>(
              context: context,
              builder: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    ListTile(title: Text('Ligne $i'), onTap: () {}),
                ],
              ),
            ),
      ),
      (
        name: 'showModalBottomSheet sur le navigateur racine',
        open: (context) => showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              builder: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    TvFocusable(
                      autofocus: i == 0,
                      onSelect: () {},
                      child: TvTestTile('Liste $i'),
                    ),
                ],
              ),
            ),
      ),
      (
        name: 'showMenu (menu d’une carte)',
        open: (context) => showMenu<String>(
              context: context,
              useRootNavigator: true,
              position: const RelativeRect.fromLTRB(400, 400, 400, 400),
              items: const [
                PopupMenuItem(value: 'a', child: Text('Marquer vu')),
                PopupMenuItem(value: 'b', child: Text('Retirer')),
              ],
            ),
      ),
      (
        name: 'route transparente (présentation de l’interface)',
        open: (context) => Navigator.of(context, rootNavigator: true).push(
              PageRouteBuilder<void>(
                opaque: false,
                barrierDismissible: true,
                pageBuilder: (_, __, ___) => Center(
                  child: TvFocusable(
                    autofocus: true,
                    onSelect: () {},
                    child: const TvTestTile('Passer'),
                  ),
                ),
              ),
            ),
      ),
      (
        name: 'confirmSettingsAction',
        open: (context) => confirmSettingsAction(
              context,
              title: 'Oublier ce serveur ?',
              message: 'Message',
              confirmLabel: 'Oublier',
            ),
      ),
      (
        name: 'showSynopsisDialog',
        open: (context) => showSynopsisDialog(
              context,
              title: 'Titre',
              overview: 'Résumé du film.',
            ),
      ),
      (
        name: 'confirmDeleteRequest',
        open: (context) => confirmDeleteRequest(context, 'Dune'),
      ),
      (
        name: 'askDeclineReason (champ différé)',
        open: (context) => askDeclineReason(context, 'Dune'),
      ),
      (
        name: 'showWatchListEditor (champs différés)',
        open: (context) => showWatchListEditor(context),
      ),
      (
        name: 'showRecoveryCodesDialog (barrière non fermable)',
        open: (context) => showRecoveryCodesDialog(context, const ['AAAA-1111']),
      ),
    ];

/// La page d'origine : deux cartes, la seconde ouvre [modal].
Widget _origin(_Modal modal) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocusable(
                autofocus: true,
                onSelect: () {},
                child: const TvTestTile('Voisine'),
              ),
              TvFocusable(
                onSelect: () => modal.open(context),
                child: const TvTestTile('Origine'),
              ),
            ],
          ),
        ),
      ),
    );

/// La route de l'élément focalisé, ou nul.
ModalRoute<Object?>? _focusedRoute() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context == null ? null : ModalRoute.of(context);
}

Future<ModalRoute<Object?>> _openFromOrigin(
    WidgetTester tester, TvNavHarness nav) async {
  final home = _focusedRoute();
  await nav.press(TraversalDirection.right);
  expect(nav.focusedLabel, 'Origine');
  await nav.select();
  await tester.pumpAndSettle();
  await TvNavHarness.settle(tester);
  final route = _focusedRoute();
  expect(route, isNotNull, reason: 'le focus est entré dans la fenêtre');
  expect(identical(route, home), isFalse,
      reason: 'le focus est entré dans la fenêtre');
  return route!;
}

void main() {
  var now = Duration.zero;
  setUp(() {
    now = Duration.zero;
    TvBack.debugClock = () => now;
  });
  tearDown(() => TvBack.debugClock = null);

  for (final modal in _modals()) {
    group(modal.name, () {
      testWidgets('le focus reste dans la fenêtre aux flèches',
          (tester) async {
        final nav = await TvNavHarness.pump(tester, _origin(modal));
        final route = await _openFromOrigin(tester, nav);
        for (final direction in TraversalDirection.values) {
          for (var i = 0; i < 3; i++) {
            await nav.press(direction);
            expect(identical(_focusedRoute(), route), isTrue,
                reason: '${direction.name} n’a pas fait sortir le focus');
          }
        }
      });

      for (final way in ['touche', 'popRoute']) {
        testWidgets('Retour ($way) la ferme et rend le focus à l’origine',
            (tester) async {
          final nav = await TvNavHarness.pump(tester, _origin(modal));
          final route = await _openFromOrigin(tester, nav);
          if (way == 'touche') {
            await nav.back();
          } else {
            await nav.popRoute();
          }
          await tester.pumpAndSettle();
          await TvNavHarness.settle(tester);
          expect(route.isActive, isFalse, reason: 'la fenêtre est fermée');
          expect(nav.focusedLabel, 'Origine');
        });
      }
    });
  }

  testWidgets(
      'DropdownButton : le menu piège le focus et le rend au bouton',
      (tester) async {
    var value = 1;
    final nav = await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => DropdownButton<int>(
              autofocus: true,
              value: value,
              items: const [
                DropdownMenuItem(value: 1, child: Text('Version 1')),
                DropdownMenuItem(value: 2, child: Text('Version 2')),
              ],
              onChanged: (v) => setState(() => value = v!),
            ),
          ),
        ),
      ),
    );
    final home = _focusedRoute();
    await nav.select();
    await tester.pumpAndSettle();
    await TvNavHarness.settle(tester);
    final menu = _focusedRoute();
    expect(identical(menu, home), isFalse);
    for (final direction in TraversalDirection.values) {
      await nav.press(direction);
      expect(identical(_focusedRoute(), menu), isTrue);
    }
    await nav.back(key: LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await TvNavHarness.settle(tester);
    expect(menu!.isActive, isFalse);
    expect(identical(_focusedRoute(), home), isTrue);
    expect(nav.focusedLabel, 'Version 1');
  });
}
