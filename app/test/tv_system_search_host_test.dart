@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L'hôte natif de la recherche du système (ADR-0129) n'est compilé que par
/// la CI de l'Apple TV, et aucun test ne l'exécute. Ce test lit ses sources
/// pour tenir ce qui peut l'être d'ici : le projet Xcode les compile toutes,
/// et les deux bouts du canal `onyx/tv_search` parlent des mêmes messages.
///
/// Un message que l'un envoie et que l'autre ne connaît pas ne lève rien :
/// l'écran resterait vide, ou une affiche ne s'ouvrirait pas.
void main() {
  final runner = Directory('tvos/Runner');
  final swift = [
    for (final file in runner.listSync().whereType<File>())
      if (file.path.endsWith('.swift')) file,
  ];
  final native = [
    for (final file in swift)
      if (file.uri.pathSegments.last.startsWith('SystemSearch'))
        file.readAsStringSync(),
  ].join('\n');
  final dart = File('lib/services/tv_system_search.dart').readAsStringSync();
  final host = File('lib/screens/search/tv_system_search_screen.dart')
      .readAsStringSync();

  Set<String> matches(String source, String pattern) => {
        for (final match in RegExp(pattern, multiLine: true).allMatches(source))
          match.group(1)!,
      };

  test('le projet Xcode compile chaque source Swift de l’hôte', () {
    final project =
        File('tvos/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final sources = project.substring(
      project.indexOf('/* Begin PBXSourcesBuildPhase section */'),
      project.indexOf('/* End PBXSourcesBuildPhase section */'),
    );
    expect(swift, isNotEmpty);
    for (final file in swift) {
      final name = file.uri.pathSegments.last;
      expect(
        sources,
        contains('/* $name in Sources */'),
        reason: '$name est dans tvos/Runner mais pas dans la phase de '
            'compilation : Xcode l’ignorerait sans rien dire',
      );
      expect(project, contains('path = $name;'));
    }
  });

  test('les deux bouts ouvrent le même canal', () {
    expect(dart, contains("MethodChannel('onyx/tv_search')"));
    expect(native, contains('name: "onyx/tv_search"'));
  });

  test('l’hôte traite chaque appel que Dart lui fait', () {
    final sent = {
      ...matches(dart, r"invokeMethod<\w+>\('(\w+)'"),
      ...matches(dart, r"_send\('(\w+)'"),
    };
    expect(sent, {'present', 'update', 'hide', 'show', 'close'});
    expect(matches(native, r'case "(\w+)":'), containsAll(sent));
  });

  test('Dart traite chaque évènement que l’hôte lui envoie', () {
    final sent = matches(native, r'invokeMethod\("(\w+)"');
    expect(sent, {'query', 'select', 'closed'});
    expect(matches(dart, r"case '(\w+)':"), containsAll(sent));
  });

  test('l’hôte lit chaque champ que Dart écrit', () {
    // Les clés des `toMap()` et de `present`, lues côté Swift par
    // `map["…"]`, `raw["…"]` ou `arguments["…"]`.
    final written = matches(dart, r"^\s*'(\w+)': ")
      ..addAll(matches(host, r"^\s*'(\w+)': AppColors\."));
    final read = {
      ...matches(native, r'(?:map|raw|arguments)\["(\w+)"\]'),
      ...matches(native, r'color\("(\w+)"'),
    };
    expect(written, containsAll(<String>[
      'id', 'title', 'subtitle', 'poster', 'badge', 'badgeTint', 'dimmed',
      'progress', 'watched', 'items', 'sections', 'emptyTitle',
      'emptyMessage', 'placeholder', 'colors', 'content', 'background',
    ]));
    expect(read, containsAll(written));
  });
}
