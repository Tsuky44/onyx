@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Depuis Flutter 3.47, `package:flutter/material.dart` et
/// `package:flutter/cupertino.dart` sont dépréciés au profit des paquets
/// `material_ui` et `cupertino_ui`. La migration est une étape à part, après
/// la montée de Flutter (ADR-0167) : ces paquets sont une copie distincte de
/// Material, et une douzaine de dépendances importent encore l'ancien.
/// D'ici là, chaque import déprécié porte un `// ignore` sur la ligne
/// d'avant.
///
/// Le plafond ne remonte pas : la migration le fait baisser. Un fichier migré
/// vers `material_ui` le libère ; baisse alors [_ceiling] au nouveau compte.
const int _ceiling = 548;

/// Les autres `// ignore: deprecated_member_use` admis, et pourquoi. Sans
/// cette liste, l'`ignore` des imports masquerait n'importe quelle
/// dépréciation.
const Map<String, String> _otherIgnores = {
  'test/support/tv_nav_harness.dart':
      '`keyEventManager.keyMessageHandler` : seul chemin pour simuler la touche '
          'Retour du système, que `flutter_test` ne sait pas nommer',
};

final RegExp _deprecatedImport =
    RegExp(r"^import 'package:flutter/(material|cupertino)\.dart'");
const String _ignore = '// ignore: deprecated_member_use';

Iterable<File> _dartFiles() sync* {
  for (final dir in const ['lib', 'test', 'tool']) {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }
}

String _path(File file) => file.path.replaceAll('\\', '/');

void main() {
  test('l’ignore de dépréciation ne couvre que les imports de Material', () {
    final offenders = <String>[];
    for (final file in _dartFiles()) {
      final path = _path(file);
      if (_otherIgnores.containsKey(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim() != _ignore) continue;
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        if (!_deprecatedImport.hasMatch(next)) offenders.add('$path:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'L’`ignore` de `deprecated_member_use` n’est admis qu’au-dessus '
          'd’un import de `flutter/material.dart` ou `flutter/cupertino.dart` '
          '(dette connue, ADR-0167). Ailleurs, migre l’appel déprécié, ou '
          'ajoute le fichier à `_otherIgnores` avec sa raison :\n\n'
          '${offenders.join('\n')}',
    );
  });

  test('chaque import déprécié de Material porte son ignore', () {
    final missing = <String>[];
    for (final file in _dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!_deprecatedImport.hasMatch(lines[i])) continue;
        if (i == 0 || lines[i - 1].trim() != _ignore) {
          missing.add('${_path(file)}:${i + 1}');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Un nouveau fichier importe de préférence '
          '`package:material_ui/material_ui.dart` une fois la migration '
          'faite. D’ici là, l’import déprécié prend `$_ignore` sur la ligne '
          'd’avant, sinon `flutter analyze` échoue en CI (ADR-0167) :\n\n'
          '${missing.join('\n')}',
    );
  });

  test('le nombre de fichiers sur l’ancien Material ne remonte pas', () {
    final count = _dartFiles()
        .where((file) => file.readAsLinesSync().any(_deprecatedImport.hasMatch))
        .length;

    expect(
      count,
      lessThanOrEqualTo(_ceiling),
      reason: '$count fichiers importent encore `flutter/material.dart` ou '
          '`flutter/cupertino.dart`, au-delà du plafond de $_ceiling. Un '
          'nouveau fichier part directement sur `material_ui` (ADR-0167).',
    );
  });
}
