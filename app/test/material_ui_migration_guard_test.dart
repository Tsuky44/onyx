@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Depuis Flutter 3.47, `package:flutter/material.dart` et
/// `package:flutter/cupertino.dart` sont dépréciés au profit des paquets
/// `material_ui` et `cupertino_ui`. L'app et nos forks de `packages/` y sont
/// passés (ADR-0168). Ces paquets sont une copie distincte de Material : un
/// widget de l'ancien Material ne voit pas le thème de l'app, et un import
/// oublié le ferait revenir sans bruit (le thème clair par défaut à l'écran).
///
/// Les seuls fichiers qui importent encore l'ancien Material, et pourquoi.
const Map<String, String> _legacyImports = {
  'lib/theme/legacy_material_bridge.dart':
      'le pont qui donne le thème de l’app aux dépendances restées sur '
          'l’ancien Material (dpad, mobile_scanner, octo_image, '
          'window_manager…) : il doit construire un ancien `Theme`',
  'test/legacy_material_bridge_test.dart':
      'vérifie ce que voit un widget de l’ancien Material sous le pont',
};

/// Les autres `// ignore: deprecated_member_use` admis, et pourquoi.
const Map<String, String> _otherIgnores = {
  'test/support/tv_nav_harness.dart':
      '`keyEventManager.keyMessageHandler` : seul chemin pour simuler la touche '
          'Retour du système, que `flutter_test` ne sait pas nommer',
};

/// Nos forks : leur code Dart est le nôtre, il suit la même règle.
const List<String> _forks = [
  '../packages/media_kit_video/lib',
  '../packages/onyx_background_downloads/lib',
  '../packages/onyx_mpv_macos/lib',
  '../packages/onyx_player_android/lib',
  '../packages/onyx_player_apple/lib',
];

final RegExp _legacyImport =
    RegExp(r"^\s*import\s+'package:flutter/(material|cupertino)\.dart'");
const String _ignore = '// ignore: deprecated_member_use';

Iterable<File> _dartFiles() sync* {
  for (final dir in const ['lib', 'test', 'tool', ..._forks]) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }
}

String _path(File file) => file.path.replaceAll('\\', '/');

void main() {
  test('plus aucun import de l’ancien Material hors des exceptions listées',
      () {
    final offenders = <String>[];
    for (final file in _dartFiles()) {
      final path = _path(file);
      if (_legacyImports.containsKey(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_legacyImport.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Importe `package:material_ui/material_ui.dart` (ou '
          '`package:cupertino_ui/cupertino_ui.dart`) : l’ancien Material ne '
          'voit pas le thème de l’app (ADR-0168). Une vraie exception va dans '
          '`_legacyImports`, avec sa raison :\n\n${offenders.join('\n')}',
    );
  });

  test('les exceptions listées existent encore', () {
    final stale = [
      for (final path in [..._legacyImports.keys, ..._otherIgnores.keys])
        if (!File(path).existsSync()) path,
      for (final path in _legacyImports.keys)
        if (File(path).existsSync() &&
            !File(path).readAsLinesSync().any(_legacyImport.hasMatch))
          path,
    ];

    expect(
      stale,
      isEmpty,
      reason: 'Une exception qui ne sert plus se retire de la liste :\n\n'
          '${stale.join('\n')}',
    );
  });

  test('l’ignore de dépréciation ne couvre que les exceptions listées', () {
    final offenders = <String>[];
    for (final file in _dartFiles()) {
      final path = _path(file);
      if (_otherIgnores.containsKey(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim() != _ignore) continue;
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        final coversListedImport =
            _legacyImports.containsKey(path) && _legacyImport.hasMatch(next);
        if (!coversListedImport) offenders.add('$path:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'L’`ignore` de `deprecated_member_use` masquerait n’importe '
          'quelle dépréciation. Migre l’appel déprécié, ou ajoute le fichier à '
          '`_otherIgnores` avec sa raison :\n\n${offenders.join('\n')}',
    );
  });

  test('chaque MaterialApp de l’app pose le pont de l’ancien Material', () {
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!RegExp(r'\bMaterialApp\(').hasMatch(source)) continue;
      if (!source.contains('LegacyMaterialBridge(')) missing.add(_path(entity));
    }

    expect(
      missing,
      isEmpty,
      reason: 'Sans `LegacyMaterialBridge` dans `MaterialApp.builder`, les '
          'widgets des dépendances restées sur l’ancien Material retombent sur '
          'le thème clair par défaut (ADR-0168) :\n\n${missing.join('\n')}',
    );
  });
}
