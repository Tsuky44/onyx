@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L'hôte natif des sons de navigation (ADR
/// `2026-11-23-fytroz-sons-de-navigation-apple-tv`) n'est compilé que par la
/// CI de l'Apple TV, et aucun test ne l'exécute. Ce test lit ses sources pour
/// tenir ce qui peut l'être d'ici, sur le modèle de
/// `tv_system_search_host_test.dart`.
///
/// Chacune de ces pannes serait muette, au sens propre : un fichier Swift
/// qu'Xcode ne compile pas, un canal que personne ne garde, un appel que
/// l'hôte ne connaît pas ne lèvent rien, l'Apple TV reste seulement
/// silencieuse.
void main() {
  const file = 'NavigationSound.swift';
  final native = File('tvos/Runner/$file').readAsStringSync();
  final delegate = File('tvos/Runner/AppDelegate.swift').readAsStringSync();
  final dart = File('lib/tv/tv_navigation_sound.dart').readAsStringSync();
  final project =
      File('tvos/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  Set<String> matches(String source, String pattern) => {
        for (final match in RegExp(pattern, multiLine: true).allMatches(source))
          match.group(1)!,
      };

  String section(String name) => project.substring(
        project.indexOf('/* Begin $name section */'),
        project.indexOf('/* End $name section */'),
      );

  /// Les commentaires citent ce que le code n'emploie pas.
  String code(String source) => source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('le projet Xcode référence, range et compile la source de l’hôte', () {
    final escaped = RegExp.escape(file);
    final reference = RegExp(
      '(\\w{24}) /\\* $escaped \\*/ = \\{isa = PBXFileReference; '
      'lastKnownFileType = sourcecode\\.swift; path = $escaped;',
    ).firstMatch(section('PBXFileReference'));
    expect(reference, isNotNull,
        reason: '$file n’a pas de PBXFileReference : Xcode ne le connaît pas');
    final referenceId = reference!.group(1)!;

    final build = RegExp(
      '(\\w{24}) /\\* $escaped in Sources \\*/ = '
      '\\{isa = PBXBuildFile; fileRef = (\\w{24}) ',
    ).firstMatch(section('PBXBuildFile'));
    expect(build, isNotNull, reason: '$file n’a pas de PBXBuildFile');
    expect(build!.group(2), referenceId,
        reason: 'le PBXBuildFile pointe sur une autre référence');

    expect(section('PBXGroup'), contains('$referenceId /* $file */,'),
        reason: '$file n’est pas rangé dans le groupe Runner');
    expect(
      section('PBXSourcesBuildPhase'),
      contains('${build.group(1)} /* $file in Sources */,'),
      reason: '$file est dans tvos/Runner mais pas dans la phase de '
          'compilation : Xcode l’ignorerait sans rien dire',
    );

    // Deux objets sous le même identifiant : Xcode n'en garde qu'un, et le
    // fichier perdu ne se compile plus.
    for (final id in [referenceId, build.group(1)!]) {
      expect(
        RegExp('^\\t\\t$id /\\*', multiLine: true).allMatches(project),
        hasLength(1),
        reason: 'l’identifiant $id sert à plusieurs objets du projet',
      );
    }
  });

  test('l’hôte monte le canal au démarrage et le garde', () {
    expect(delegate, contains('NavigationSoundChannel(messenger:'));
    // Sans propriété qui le retient, l'objet est libéré à la fin de la
    // fonction, et son gestionnaire (`[weak self]`) ne répond plus.
    expect(
      delegate,
      contains('private var navigationSound: NavigationSoundChannel?'),
    );
    expect(delegate, contains('navigationSound = NavigationSoundChannel('));
  });

  test('les deux bouts ouvrent le même canal', () {
    expect(dart, contains("MethodChannel('onyx/tv_navigation_sound')"));
    expect(native, contains('name: "onyx/tv_navigation_sound"'));
  });

  test('l’hôte traite chaque appel que Dart lui fait, et aucun autre', () {
    final sent = {
      ...matches(dart, r"_play\('(\w+)'"),
      ...matches(dart, r"_invoke\('(\w+)'"),
    };
    expect(sent, {'prepare', 'move', 'push', 'pop'});
    expect(matches(native, r'case "(\w+)":'), sent);
  });

  test('l’hôte joue hors de la session audio de l’app', () {
    final source = code(native);
    expect(source, contains('AudioServicesPlaySystemSound('));
    expect(
      source,
      isNot(contains(RegExp(r'AVAudio|AVFoundation|AVFAudio|AVPlayer'))),
      reason: 'Un AVAudioPlayer passe par l’AVAudioSession de l’app, que '
          'seul le lecteur active (une session activée trop tôt fige la '
          'route audio en stéréo, voir AppDelegate) et qui peut couper ou '
          'baisser ce qui joue ailleurs. Les sons de navigation passent par '
          'System Sound Services, qui n’y touche pas.',
    );
  });

  test('les sons sont ceux du système, lus sur l’appareil, jamais embarqués',
      () {
    final source = code(native);
    expect(source, contains('"/System/Library/Audio/UISounds/"'));
    final sounds = matches(source, r'file: "([\w.]+)"');
    expect(sounds, {
      'focus_change_small.caf',
      'navigation_push.caf',
      'navigation_pop.caf',
    });
    expect(source, isNot(contains('Bundle.main')));

    // Ces fichiers sont à Apple : les copier dans le dépôt ou dans l'app
    // serait les redistribuer.
    final shipped = [
      for (final root in ['tvos/Runner', 'assets'])
        if (Directory(root).existsSync())
          for (final entity in Directory(root).listSync(recursive: true))
            if (entity is File &&
                sounds.contains(entity.uri.pathSegments.last))
              entity.path,
    ];
    expect(shipped, isEmpty,
        reason: 'Un son du système est embarqué : $shipped. L’hôte les lit '
            'dans /System/Library/Audio/UISounds/, il ne les distribue pas.');
  });
}
