import 'dart:convert';

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/settings/widgets/folder_picker.dart';
import 'package:onyx/screens/settings/widgets/library_editor_dialog.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_doubles.dart';

/// L'explorateur de dossiers du serveur (ADR-0165) : un seul widget pour
/// l'éditeur de bibliothèque et l'assistant. Il ne parle pas à `ApiClient`,
/// donc ces tests lui donnent un faux serveur de dossiers.

FsFolder _folder(
  String path, {
  LibraryKind kind = LibraryKind.movies,
  bool covered = false,
  int videos = 12,
  bool capped = false,
}) =>
    FsFolder(
      name: path.split('/').last,
      path: path,
      kind: kind,
      covered: covered,
      videoCount: videos,
      videoCountCapped: capped,
    );

FsListing _listing(
  String path,
  List<FsFolder> folders, {
  bool emptyRoot = false,
  bool readable = true,
}) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  return FsListing(
    root: '/media',
    path: path,
    parent: path == '/media' ? null : '/${parts.take(parts.length - 1).join('/')}',
    breadcrumb: [
      for (var i = 0; i < parts.length; i++)
        FsCrumb(name: parts[i], path: '/${parts.take(i + 1).join('/')}'),
    ],
    folders: folders,
    readable: readable,
    emptyRoot: emptyRoot,
  );
}

/// Un petit disque : `/media` contient Films, Séries (déjà prise) et Concerts.
class _Disk {
  final List<String?> asked = [];

  Future<FsListing?> call(String? path) async {
    asked.add(path);
    return switch (path) {
      null || '/media' => _listing('/media', [
          _folder('/media/Films', videos: 124),
          _folder('/media/Séries',
              kind: LibraryKind.shows, covered: true, videos: 300),
          _folder('/media/Concerts',
              kind: LibraryKind.other, videos: 50, capped: true),
        ]),
      '/media/Films' => _listing('/media/Films', [
          _folder('/media/Films/Animation', videos: 8),
        ]),
      '/media/Films/Animation' => _listing('/media/Films/Animation', []),
      '/media/Concerts' => _listing('/media/Concerts', []),
      _ => throw DioException(
          requestOptions: RequestOptions(path: '/api/fs/browse'),
          response: Response(
              requestOptions: RequestOptions(path: '/api/fs/browse'),
              statusCode: 404),
        ),
    };
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required FolderLoader loader,
  required ValueChanged<FolderPick> onChoose,
  VoidCallback? onUnsupported,
  String? initialPath,
  bool tv = false,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: TvScope(
      isTv: tv,
      child: Scaffold(
        body: SingleChildScrollView(
          child: FolderPicker(
            loadFolder: loader,
            onChoose: onChoose,
            onUnsupported: onUnsupported,
            initialPath: initialPath,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('contrat : ce que le serveur répond', () {
    test('un dossier de /api/fs/browse', () {
      final listing = FsListing.fromJson(jsonDecode('''
{"root":"/media","path":"/media/Films","parent":"/media",
 "breadcrumb":[{"name":"media","path":"/media"},{"name":"Films","path":"/media/Films"}],
 "folders":[{"name":"Animation","path":"/media/Films/Animation","kind":"movies",
             "covered":true,"video_count":50,"video_count_capped":true}],
 "readable":true,"empty_root":false}''') as Map<String, dynamic>);

      expect(listing.parent, '/media');
      expect([for (final c in listing.breadcrumb) c.name], ['media', 'Films']);
      final folder = listing.folders.single;
      expect(folder.kind, LibraryKind.movies);
      expect(folder.covered, isTrue);
      expect(folder.videoCount, 50);
      expect(folder.videoCountCapped, isTrue);
      expect(listing.emptyRoot, isFalse);
    });

    test('à la racine, le dossier du dessus est null', () {
      final listing = FsListing.fromJson({
        'root': '/media',
        'path': '/media',
        'parent': null,
        'breadcrumb': [],
        'folders': [],
        'readable': true,
        'empty_root': true,
      });
      expect(listing.parent, isNull);
      expect(listing.emptyRoot, isTrue);
    });
  });

  testWidgets('la racine liste ses dossiers avec le type et le nombre de vidéos',
      (tester) async {
    await _pump(tester, loader: _Disk().call, onChoose: (_) {});

    expect(find.text('Films'), findsWidgets);
    expect(find.text('Films · 124 vidéos'), findsOneWidget);
    // Le serveur cesse de compter à un plafond : « 50+ ».
    expect(find.text('Autre · 50+ vidéos'), findsOneWidget);
  });

  testWidgets('un dossier déjà utilisé est grisé et ne s’ouvre pas',
      (tester) async {
    final disk = _Disk();
    await _pump(tester, loader: disk.call, onChoose: (_) {});

    expect(find.text('Déjà utilisé par une bibliothèque'), findsOneWidget);
    await tester.tap(find.text('Séries'));
    await tester.pumpAndSettle();
    expect(disk.asked, [null],
        reason: 'un dossier pris ne se parcourt pas, il n’est pas rechargé');
  });

  testWidgets('ouvrir un dossier le parcourt, et le fil d’Ariane ramène en haut',
      (tester) async {
    final disk = _Disk();
    await _pump(tester, loader: disk.call, onChoose: (_) {});

    await tester.tap(find.text('Films · 124 vidéos'));
    await tester.pumpAndSettle();
    expect(disk.asked.last, '/media/Films');
    expect(find.text('Animation'), findsOneWidget);

    // « media » est une miette cliquable ; « Films », le dossier ouvert, non.
    await tester.tap(find.widgetWithText(TextButton, 'media'));
    await tester.pumpAndSettle();
    expect(disk.asked.last, '/media');
    expect(find.text('Concerts'), findsOneWidget);
  });

  testWidgets('« Choisir ce dossier » rend le dossier ouvert et son type deviné',
      (tester) async {
    FolderPick? picked;
    await _pump(tester, loader: _Disk().call, onChoose: (p) => picked = p);

    await tester.tap(find.text('Films · 124 vidéos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir ce dossier'));
    await tester.pump();

    expect(picked?.path, '/media/Films');
    expect(picked?.name, 'Films');
    expect(picked?.kind, LibraryKind.movies);
  });

  testWidgets('un sous-dossier vide se choisit quand même', (tester) async {
    FolderPick? picked;
    await _pump(tester,
        loader: _Disk().call,
        initialPath: '/media/Films/Animation',
        onChoose: (p) => picked = p);

    expect(find.textContaining('Aucun sous-dossier'), findsOneWidget);
    await tester.tap(find.text('Choisir ce dossier'));
    await tester.pump();
    expect(picked?.path, '/media/Films/Animation');
  });

  testWidgets('un dossier disparu ramène à la racine', (tester) async {
    final disk = _Disk();
    await _pump(tester,
        loader: disk.call, initialPath: '/media/Disparu', onChoose: (_) {});

    expect(disk.asked, ['/media/Disparu', null]);
    expect(find.text('Concerts'), findsOneWidget);
  });

  testWidgets(
      'une racine vide dit de monter le dossier dans le compose, avec la ligne',
      (tester) async {
    FolderPick? picked;
    await _pump(
      tester,
      loader: (_) async => _listing('/media', [], emptyRoot: true),
      onChoose: (p) => picked = p,
    );

    expect(find.textContaining('montez votre dossier dans le compose'),
        findsOneWidget);
    expect(find.textContaining('/media/Films:ro'), findsOneWidget);
    // Rien à choisir dans une racine vide.
    await tester.tap(find.text('Choisir ce dossier'), warnIfMissed: false);
    expect(picked, isNull);
  });

  testWidgets('un dossier illisible le dit', (tester) async {
    await _pump(
      tester,
      loader: (_) async => _listing('/media', [], readable: false),
      onChoose: (_) {},
    );
    expect(find.textContaining('pas le droit de lire'), findsOneWidget);
  });

  testWidgets('un serveur qui ne sait pas explorer le dit à l’appelant',
      (tester) async {
    var unsupported = 0;
    await _pump(
      tester,
      loader: (_) async => null,
      onChoose: (_) {},
      onUnsupported: () => unsupported++,
    );
    expect(unsupported, 1);
    expect(find.text('Choisir ce dossier'), findsNothing);
  });

  testWidgets('au D-pad, bas parcourt la liste et OK ouvre le dossier',
      (tester) async {
    final disk = _Disk();
    await _pump(tester, loader: disk.call, onChoose: (_) {}, tv: true);

    // La liste est atteignable à la télécommande : le focus entre dans la
    // première ligne ouvrable, et OK l'ouvre.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    var guard = 0;
    while (!_focusedIsFolderRow(tester, 'Films') && guard++ < 12) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(_focusedIsFolderRow(tester, 'Films'), isTrue,
        reason: 'la ligne « Films » doit recevoir le focus au D-pad');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(disk.asked.last, '/media/Films');
  });

  group('dans l’éditeur de bibliothèque', () {
    Future<List<LibraryDraft>> openEditor(
      WidgetTester tester, {
      required FolderLoader? browse,
    }) async {
      final drafts = <LibraryDraft>[];
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLibraryEditor(
              context,
              onSubmit: (draft) async => drafts.add(draft),
              browse: browse,
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return drafts;
    }

    testWidgets(
        'choisir un dossier préremplit le nom et le type (ADR-0155)',
        (tester) async {
      final drafts = await openEditor(tester, browse: _Disk().call);

      await tester.tap(find.text('Autre · 50+ vidéos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir ce dossier'));
      await tester.pumpAndSettle();

      expect(find.text('/media/Concerts'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(drafts.single,
          (name: 'Concerts', kind: LibraryKind.other, path: '/media/Concerts'));
    });

    testWidgets('un nom tapé à la main n’est pas écrasé par le dossier',
        (tester) async {
      final drafts = await openEditor(tester, browse: _Disk().call);

      await tester.enterText(find.byType(TextField).first, 'Mes films');
      await tester.tap(find.text('Films · 124 vidéos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir ce dossier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(drafts.single.name, 'Mes films');
      expect(drafts.single.path, '/media/Films');
    });

    testWidgets('la saisie à la main reste possible sous « Avancé »',
        (tester) async {
      final drafts = await openEditor(tester, browse: _Disk().call);

      await tester.enterText(find.byType(TextField).first, 'Perso');
      await tester.tap(find.textContaining('Avancé'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '/media/perso');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(drafts.single.path, '/media/perso');
    });

    testWidgets(
        'un serveur qui ne sait pas explorer garde le chemin tapé d’avant',
        (tester) async {
      await openEditor(tester, browse: (_) async => null);

      expect(find.text('Choisir ce dossier'), findsNothing);
      expect(find.textContaining('Avancé'), findsNothing);
      // Le champ « Dossier » est là, sans repli : le nom et le chemin.
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('l’API de l’explorateur', () {
    ResponseBody json(Object body, [int status = 200]) =>
        ResponseBody.fromString(jsonEncode(body), status, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });

    test('sans path, la racine ; avec path, le dossier demandé', () async {
      final requests = <String>[];
      final api = ApiClient(
          httpClient: Dio()
            ..httpClientAdapter = Adapter((options) {
              requests.add('${options.uri.path}?${options.uri.query}');
              return json({
                'root': '/media',
                'path': '/media',
                'parent': null,
                'breadcrumb': [],
                'folders': [],
                'readable': true,
                'empty_root': false,
              });
            }));

      await api.browseFolders();
      await api.browseFolders(path: '/media/Films');
      expect(requests, [
        '/api/fs/browse?',
        '/api/fs/browse?path=%2Fmedia%2FFilms',
      ]);
    });

    test('un vieux serveur (404 sur la racine) rend null, sans lever',
        () async {
      final api = ApiClient(
          httpClient: Dio()
            ..httpClientAdapter =
                Adapter((_) => json({'error': 'not found'}, 404)));
      expect(await api.browseFolders(), isNull);
    });

    test('un chemin hors racine (400) lève, l’explorateur repart de la racine',
        () async {
      final api = ApiClient(
          httpClient: Dio()
            ..httpClientAdapter =
                Adapter((_) => json({'error': 'hors racine'}, 400)));
      expect(() => api.browseFolders(path: '/etc'), throwsA(isA<DioException>()));
    });
  });
}

/// Vrai quand le focus est sur la ligne de dossier de [name] (le nom du dossier
/// est dans la ligne qui contient le nœud focalisé).
bool _focusedIsFolderRow(WidgetTester tester, String name) {
  final focused = FocusManager.instance.primaryFocus;
  final context = focused?.context;
  if (context == null) return false;
  var found = false;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Row || widget is InkWell) {
      // Cherche le nom parmi les descendants de la ligne.
      void walk(Element e) {
        if (found) return;
        final w = e.widget;
        if (w is Text && w.data == name) found = true;
        e.visitChildren(walk);
      }

      walk(element);
      return !found;
    }
    return true;
  });
  return found;
}
