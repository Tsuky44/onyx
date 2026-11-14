import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media.dart';
import 'package:onyx/models/offline_download.dart';
import 'package:onyx/screens/downloads/downloads_screen.dart';
import 'package:onyx/screens/downloads/widgets/download_row.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/services/server_reachability.dart';
import 'package:onyx/widgets/global/onyx_dialog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

/// L'écran des téléchargements hors téléviseur (maquette « 6 ·
/// Téléchargements ») : des sections par état, une seule action visible par
/// ligne, le reste dans le menu Onyx, et une suppression qui demande d'abord.
///
/// Le vrai [DownloadManager] relit un manifeste jetable, comme
/// `downloads_navigation_map_test.dart`. Rien n'y est « en téléchargement » :
/// le gestionnaire relancerait la file au chargement, et donc le réseau.

class _ApiAtNas extends ApiClient {
  @override
  String get baseUrl => 'http://nas:8080';
}

class _TempSupportDirectory extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempSupportDirectory(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Map<String, dynamic> _item(int id, String title, String status) => {
      'media_id': id,
      'type': 'movie',
      'title': title,
      'file_name': 'video.mkv',
      'added_at': '2026-09-0${10 - id}T12:00:00.000Z',
      'server_url': 'http://nas:8080',
      'duration': 6000,
      'status': status,
      'bytes_received': status == 'completed' ? 1000 : 400,
      'bytes_total': 1000,
      'needs_sync': false,
      if (status == 'failed') 'error': 'Disque plein',
    };

Widget _host(Widget child) {
  final api = _ApiAtNas();
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<DownloadManager>.value(
          value: DownloadManager.instance),
      ChangeNotifierProvider<ServerReachability>(
          create: (_) => ServerReachability(api)),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('onyx_downloads_pc_test');
    PathProviderPlatform.instance = _TempSupportDirectory(root.path);
    final store = Directory('${root.path}/onyx_offline')
      ..createSync(recursive: true);
    File('${store.path}/manifest.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'items': [
        _item(1, 'Film en pause', 'paused'),
        _item(2, 'Film en échec', 'failed'),
        _item(3, 'Film A', 'completed'),
        _item(4, 'Film B', 'completed'),
      ],
    }));
    await DownloadManager.instance.initialize(_ApiAtNas());
  });

  tearDownAll(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Laissé au système : c'est un dossier temporaire.
    }
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const DownloadsScreen()));
    await tester.pump();
  }

  testWidgets('les lignes se rangent par état : en cours, puis sur l’appareil',
      (tester) async {
    await pumpScreen(tester);
    final inProgress = find.text('EN COURS · 2');
    final onDevice = find.text('SUR CET APPAREIL · 2');
    expect(inProgress, findsOneWidget);
    expect(onDevice, findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(inProgress), lessThan(top(find.text('Film en pause'))));
    expect(top(find.text('Film en échec')), lessThan(top(onDevice)));
    expect(top(onDevice), lessThan(top(find.text('Film A'))));
  });

  testWidgets('l’action visible suit l’état, le menu est celui d’Onyx',
      (tester) async {
    await pumpScreen(tester);
    // Un échec : la pastille et « Réessayer ».
    expect(find.text('Échec'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    // Deux terminés : deux lectures.
    expect(find.byTooltip('Lire'), findsNWidgets(2));
    // Une pause n'a pas d'action visible ; la reprise est dans le menu.
    expect(find.byTooltip('Mettre en pause'), findsNothing);
    // Le type des choix du menu est privé : on compte les menus par leur
    // tooltip.
    expect(find.byTooltip('Plus d’actions'), findsNWidgets(4));
    expect(find.byType(PopupMenuButton<String>), findsNothing,
        reason: 'l’ancien menu Material reste réservé à la TV');
  });

  testWidgets('un téléchargement qui descend montre sa pause en verre',
      (tester) async {
    final entry = OfflineDownload(
      mediaId: 99,
      type: MediaType.movie,
      title: 'Film qui descend',
      fileName: 'video.mkv',
      addedAt: DateTime(2026, 9, 1),
      status: DownloadStatus.downloading,
      bytesReceived: 300,
      bytesTotal: 1000,
    );
    await tester.pumpWidget(_host(Scaffold(body: DownloadRow(entry: entry))));
    expect(find.byTooltip('Mettre en pause'), findsOneWidget);
    expect(find.byTooltip('Lire'), findsNothing);
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.3, 1e-9));
    expect(bar.minHeight, 3);
  });

  testWidgets('Supprimer passe par le menu et une confirmation destructive',
      (tester) async {
    await pumpScreen(tester);
    final lastMenu = find.byTooltip('Plus d’actions').last;
    await tester.tap(lastMenu);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<OnyxDialog>(find.byType(OnyxDialog));
    expect(dialog.destructive, isTrue);
    expect(find.text('Supprimer le téléchargement ?'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(OnyxDialog), findsNothing);
    expect(DownloadManager.instance.downloads, hasLength(4),
        reason: 'annuler ne supprime rien');
  });
}
