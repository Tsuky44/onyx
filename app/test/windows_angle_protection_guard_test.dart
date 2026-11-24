@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// En 3.50, l'app Windows plantait au lancement une fois sur trois à une fois
/// sur dix, dans le pilote graphique : ANGLE ne protège plus le contexte
/// D3D11 quand le fil raster présente une image pendant que le fil IO envoie
/// une image décodée (flutter/flutter#196618). Le runner active la protection
/// multithread de l'appareil D3D11 de Flutter (ADR-0167). Ces gardes
/// empêchent de la perdre en route, et imposent de refaire la mesure à chaque
/// montée de Flutter.

/// La version de Flutter avec laquelle `tool/windows_launch_stress.ps1` a été
/// passé, sans aucun arrêt, sur une machine avec un vrai GPU.
const String _stressedFlutter = '3.50.1';

/// La ligne que le runner écrit quand la protection est active, et que le
/// script de lancements cherche.
const String _activeLine = 'protection multithread D3D11 active';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('le runner pose la protection avant de créer le moteur', () {
    final window = _read('windows/runner/flutter_window.cpp');
    final install = window.indexOf('angle_multithread_protection::Install()');
    final controller =
        window.indexOf('std::make_unique<flutter::FlutterViewController>');

    expect(install, isNot(-1),
        reason: 'flutter_window.cpp n’appelle plus '
            '`angle_multithread_protection::Install()` : la 3.50 replante au '
            'lancement (ADR-0167, flutter/flutter#196618).');
    expect(controller, isNot(-1));
    expect(install, lessThan(controller),
        reason: 'La protection se pose avant la création du '
            'FlutterViewController : c’est lui qui crée l’appareil D3D11 '
            'd’ANGLE, et l’appareil doit être protégé avant sa première image.');
    expect(_read('windows/runner/CMakeLists.txt'),
        contains('"angle_multithread_protection.cpp"'));
  });

  test('la protection vise l’appareil D3D11 de Flutter', () {
    final source = _read('windows/runner/angle_multithread_protection.cpp');

    expect(source, contains('L"flutter_windows.dll"'),
        reason: 'L’ANGLE de Flutter est dans flutter_windows.dll ; le '
            'libEGL.dll livré à côté est celui de libmpv.');
    expect(source, contains('"D3D11CreateDevice"'));
    expect(source, contains('SetMultithreadProtected(TRUE)'));
    expect(source, contains(_activeLine),
        reason: 'Le script de lancements reconnaît la protection à cette '
            'ligne.');
  });

  test('le script de lancements cherche la ligne du runner', () {
    final script = _read('tool/windows_launch_stress.ps1');

    expect(script, contains(_activeLine));
    expect(script, contains('exit 1'),
        reason: 'Le script doit échouer sur un arrêt ou sans protection.');
  });

  test('chaque montée de Flutter repasse le test de lancements', () {
    final pubspec = _read('pubspec.yaml');
    final match = RegExp(r"flutter: '>=([0-9.]+)'").firstMatch(pubspec);

    expect(match, isNotNull,
        reason: 'pubspec.yaml ne fixe plus de version minimale de Flutter.');
    expect(
      match!.group(1),
      _stressedFlutter,
      reason: 'Flutter est passé à ${match.group(1)}. Sur une machine Windows '
          'avec un vrai GPU, lance '
          '`powershell -File tool\\windows_launch_stress.ps1 -Exe <app.exe>` '
          'puis la même chose avec `-Skia` (build profile) : 40 lancements '
          'chacun, aucun arrêt attendu. Regarde aussi si le moteur active '
          'lui-même la protection (flutter/flutter#196897, prévu en 3.50.2) '
          'et si ANGLE est corrigé (flutter/flutter#197238) : le détour du '
          'runner peut alors partir. Note le résultat dans l’ADR-0167, puis '
          'mets `_stressedFlutter` à ${match.group(1)}.',
    );
  });
}
