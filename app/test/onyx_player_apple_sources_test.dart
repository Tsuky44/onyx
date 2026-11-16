@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le lecteur Apple n'a qu'un code Swift, et deux endroits où il doit vivre.
///
/// SwiftPM ne sert à Flutter que `darwin/` pour iPhone et Mac, et flutter-tvos
/// ne lit que `tvos/`. Un paquet Swift ne peut pas désigner des sources hors de
/// son dossier, et un lien symbolique ne survit pas à un clone sous Windows :
/// `tvos/` porte donc une copie, écrite par `tool/sync_tvos.dart`. Ce test
/// empêche la copie de dériver — une correction faite d'un côté seulement ne
/// se verrait que sur une Apple TV.
const _package = '../packages/onyx_player_apple';
const _darwin = '$_package/darwin/onyx_player_apple/Sources/onyx_player_apple';
const _tvos = '$_package/tvos/Sources/onyx_player_apple';

const _fix = 'Lancer `dart run tool/sync_tvos.dart` depuis '
    'packages/onyx_player_apple.';

Map<String, String> _swiftSources(String dir) => {
      for (final file in Directory(dir).listSync().whereType<File>())
        file.uri.pathSegments.last:
            file.readAsStringSync().replaceAll('\r\n', '\n'),
    };

void main() {
  test('les sources Swift de l’Apple TV sont celles d’iPhone et Mac', () {
    final darwin = _swiftSources(_darwin);
    final tvos = _swiftSources(_tvos);

    expect(tvos.keys.toSet(), darwin.keys.toSet(),
        reason: 'Les deux dossiers ne portent pas les mêmes fichiers. $_fix');
    final drifted = [
      for (final name in darwin.keys)
        if (tvos[name] != darwin[name]) name,
    ];
    expect(drifted, isEmpty,
        reason: 'Copie tvOS périmée pour ${drifted.join(', ')}. $_fix');
  });

  test('le code généré par Pigeon importe Flutter sur l’Apple TV', () {
    // Pigeon n'importe `Flutter` que sous `os(iOS)` : régénérer le contrat sans
    // repasser le script casse la compilation tvOS, et seulement elle.
    final generated = File('$_darwin/Messages.g.swift').readAsStringSync();
    expect(generated, contains('#if os(iOS) || os(tvOS)\n  import Flutter'),
        reason: 'Garde d’import de Pigeon non corrigée. $_fix');
  });

  test('les deux paquets Swift épinglent le même AetherEngine', () {
    // Un FFmpeg par build, et le même sur les trois appareils : une Apple TV
    // qui lit autrement qu'un iPhone serait un bug qu'on ne reproduit pas.
    String requirement(String manifest) {
      final source = File(manifest).readAsStringSync();
      final match =
          RegExp(r'AetherEngine",\s*(\.upToNextMinor\(from: "[^"]+"\))')
              .firstMatch(source);
      expect(match, isNotNull,
          reason: '$manifest ne dépend plus d’AetherEngine');
      return match!.group(1)!;
    }

    expect(
      requirement('$_package/tvos/Package.swift'),
      requirement('$_package/darwin/onyx_player_apple/Package.swift'),
    );
  });

  test('un chargement repris par le moteur rend la main au play() de Dart', () {
    // Une piste audio choisie pendant l'ouverture fait reconstruire la
    // session par le moteur (ADR-0093) : `load` lève alors
    // `CancellationError` sans que notre tâche soit annulée, et la session
    // revient en pause. Tant que `loadTask` restait posé, `play()` retenait sa
    // demande pour une fin de chargement qui ne venait plus — vingt-cinq
    // secondes d'attente puis « La lecture ne démarre pas » devant une
    // session prête (journal iOS 1.1.52). Seul Xcode compile ce fichier : ce
    // test tient la règle faute de pouvoir l'exécuter.
    final player = File('$_darwin/AetherPlayer.swift').readAsStringSync();
    final superseded = RegExp(
      r'catch is CancellationError \{(.*?)\n      \} catch \{',
      dotAll: true,
    ).firstMatch(player)?.group(1);

    expect(superseded, isNotNull,
        reason: 'L’ouverture ne distingue plus un chargement remplacé.');
    expect(superseded, contains('guard !Task.isCancelled else { return }'),
        reason: 'Une ouverture plus récente doit garder la main : seule la '
            'reprise par le moteur libère `loadTask`.');
    expect(superseded, contains('self.loadTask = nil'),
        reason: '`loadTask` reste posé après une reprise par le moteur : '
            'play() est retenu pour toujours.');
    expect(superseded, contains('self.deliverWantedTransport()'),
        reason: 'Le play() demandé pendant le chargement n’est plus porté '
            'au moteur : la session reste en pause.');
  });

  test('le fichier brut est servi en segments progressifs (ADR-0093)', () {
    // Sans ce réglage, le premier segment d'un remux 4K attend sa coupe
    // entière (~1,1 s mesuré). Il ne vaut que pour le fichier brut : le HLS
    // de transcodage du serveur ne passe pas par la boucle locale.
    final player = File('$_darwin/AetherPlayer.swift').readAsStringSync();
    expect(player, contains('options.progressiveSegmentDelivery = isRawFile'),
        reason: 'Démarrage progressif retiré : le premier segment attend '
            'de nouveau sa coupe entière (ADR-0093).');
  });
}
