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

  test('une session HLS du serveur va droit à AVPlayer', () {
    // Sans `nativeRemoteHLS`, le moteur tente de démultiplexer la playlist
    // comme un fichier, échoue, la relit et télécharge la tête du premier
    // segment avant de la confier à AVPlayer : des allers-retours et un
    // segment payés à chaque changement de qualité, pour une vérification
    // (HEVC en MPEG-TS) que nos segments fMP4 ne déclenchent jamais. Seul
    // Xcode compile ce fichier : ce test tient la règle.
    final player = File('$_darwin/AetherPlayer.swift').readAsStringSync();
    expect(player, contains('options.nativeRemoteHLS = !isRawFile'));
  });

  test('le natif dit quand la première image est à l’écran', () {
    // Le cache du lecteur se lève sur le verrou du moteur, pas sur l'horloge
    // qui avance : la couche vidéo tient une image avant que la réserve ne
    // laisse partir la lecture. Il faut l'état dans l'instantané, et un
    // instantané quand il change.
    final player = File('$_darwin/AetherPlayer.swift').readAsStringSync();
    expect(player,
        contains('firstFrameShown: engine.hasFirstFrameReadyForDisplay'));
    expect(player,
        contains(r'Self.signal(engine.$hasFirstFrameReadyForDisplay)'));
  });

  test('le démarrage part plus tôt sur une réserve qui grossit vite', () {
    // Deux seuils, et la règle qui choisit entre eux : 2 s de réserve, ou
    // 1 s quand elle se remplit au moins deux fois plus vite qu'elle ne se
    // lit. Le second sans le premier ferait caler une ligne juste.
    final fastStart = File('$_darwin/FastStart.swift').readAsStringSync();
    expect(fastStart, contains('static let minimumBufferAhead: Double = 2.0'));
    expect(fastStart,
        contains('static let minimumGrowingBufferAhead: Double = 1.0'));
    expect(fastStart, contains('static let minimumFillRate: Double = 2.0'));
    expect(fastStart,
        contains('guard Self.isEnough(ahead: ahead, fillRate: fillRate)'));
  });

  test('l’appareil dit s’il décode le HEVC en matériel', () {
    // La même question qu'AetherEngine pose avant de choisir sa route : sans
    // elle, une Apple TV HD ouvre en Direct Play ce qu'elle décode en
    // logiciel.
    final host = File('$_darwin/PlayerHost.swift').readAsStringSync();
    expect(
        host,
        contains(
            'hardwareHevc: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)'));
    expect(host, contains('import VideoToolbox'));
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

  test('une session démontée en arrière-plan est reconstruite avant de lire',
      () {
    // Sur l'Apple TV, tout passage en arrière-plan (économiseur d'écran
    // derrière une pause, bouton TV, veille) fait démonter au moteur son
    // pipeline vidéo et le laisse en `.paused` : il attend de l'hôte qu'il le
    // reconstruise (`needsForegroundVideoRestore`). Personne ne le faisait.
    // play() partait sur un lecteur sans item : l'état passait à `.playing`,
    // la phase restait `.loading`, et le film restait bloqué en pause quoi
    // qu'on presse. Seul Xcode compile ce fichier : ce test tient la règle.
    final player = File('$_darwin/AetherPlayer.swift').readAsStringSync();
    String? body(String signature) => RegExp(
          '${RegExp.escape(signature)} \\{(.*?)\\n  \\}\\n',
          dotAll: true,
        ).firstMatch(player)?.group(1);

    final restore =
        body('private func restoreAfterBackground(at positionMs: Int64? = nil)');
    expect(restore, isNotNull,
        reason: 'Plus personne ne reconstruit la session démontée.');
    expect(restore, contains('engine.needsForegroundVideoRestore'),
        reason: 'La reconstruction ne vaut que pour une session démontée.');
    expect(restore, contains('!isInBackground'),
        reason: 'Reconstruire en arrière-plan fait traverser la veille de '
            'l’Apple TV à un décodeur : c’est ce que le démontage évite.');
    expect(restore, contains('try await self.engine.reloadAtCurrentPosition()'));
    expect(restore, contains('self.deliverWantedTransport()'),
        reason: 'La session doit revenir dans l’état demandé, pas dans '
            'celui de son premier montage.');

    for (final command in ['func play()', 'func seek(toMs positionMs: Int64)']) {
      expect(body(command), contains('restoreAfterBackground('),
          reason: '`$command` part sur une session démontée : rien ne lit.');
    }
    // Le moteur remet son horloge à zéro pendant la reconstruction : une
    // reconstruction qui échoue rouvrait sinon le film à la seconde zéro.
    expect(restore, contains('restoringAtMs = positionMs ??'));
    expect(player, contains('if let held = self.restoringAtMs'),
        reason: 'La position rapportée retombe à zéro pendant la '
            'reconstruction.');
    final play = body('func play()')!;
    expect(
      play.indexOf('restoreAfterBackground()'),
      lessThan(play.indexOf('engine.play()')),
      reason: 'play() doit attendre la reconstruction, pas la devancer.',
    );
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
