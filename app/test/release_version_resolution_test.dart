@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La version d'une publication se calcule seule, à partir de ce qui est
/// déjà sorti (`scripts/ci/resolve-version.sh`).
///
/// Une plateforme peut sortir seule (l'Apple TV sur TestFlight, par
/// `tvos.yml`). Tant que rien ne notait sa version, la publication globale
/// suivante repartait du dernier tag `vX.Y.Z`, retombait sur le numéro de
/// l'Apple TV, et Apple refusait son envoi. Il fallait s'en souvenir et taper
/// la version à la main. Ces tests tiennent la règle : une plateforme seule
/// reste sur la version qu'elle a ouverte, une publication globale part de la
/// plus haute version connue.
const _script = '../scripts/ci/resolve-version.sh';
const _release = '../.github/workflows/release.yml';
const _tvos = '../.github/workflows/tvos.yml';

void main() {
  // Le script est du bash, lancé par les runners Linux et macOS de la CI.
  final skip = Platform.isWindows ? 'bash absent sous Windows' : null;

  late Directory repo;
  late Directory origin;
  late String script;

  String git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: repo.path);
    expect(result.exitCode, 0, reason: 'git ${args.join(' ')}: ${result.stderr}');
    return (result.stdout as String).trim();
  }

  ProcessResult run(List<String> args) => Process.runSync(
        'bash',
        [script, ...args],
        workingDirectory: repo.path,
      );

  String version(List<String> args) {
    final result = run(args);
    expect(result.exitCode, 0, reason: '${args.join(' ')}: ${result.stderr}');
    return (result.stdout as String).trim();
  }

  setUp(() {
    script = File(_script).absolute.path;
    origin = Directory.systemTemp.createTempSync('onyx-version-origin');
    repo = Directory.systemTemp.createTempSync('onyx-version');
    Process.runSync('git', ['init', '-q', '--bare', origin.path]);
    git(['init', '-q']);
    git(['remote', 'add', 'origin', origin.path]);
    git([
      '-c', 'user.name=test', '-c', 'user.email=test@example.invalid', //
      'commit', '-q', '--allow-empty', '-m', 'init',
    ]);
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    origin.deleteSync(recursive: true);
  });

  group('une publication globale', () {
    test('part du dernier tag quand aucune plateforme n’est sortie seule', () {
      git(['tag', 'v1.0.9']);
      git(['tag', 'v1.0.34']);
      // Tri numérique : un tri alphabétique placerait 1.0.9 après 1.0.34.
      expect(version(['release', 'test']), '1.0.35');
      expect(version(['release', 'prod']), '1.1.0');
      expect(version(['release', 'major']), '2.0.0');
      expect(version(['latest-release']), '1.0.34');
    }, skip: skip);

    test('passe au-dessus d’une Apple TV sortie seule, et tout s’y aligne',
        () {
      git(['tag', 'v1.2.0']);
      git(['tag', 'build/tvos/1.2.1']);
      // Reprise en 1.2.1, elle verrait son envoi Apple TV refusé : Apple a
      // déjà reçu cette version avec un numéro de build plus grand.
      expect(version(['release', 'test']), '1.2.2');
      expect(version(['release', 'prod']), '1.3.0');
      // Le résumé du run, lui, dit toujours la dernière publication globale.
      expect(version(['latest-release']), '1.2.0');
    }, skip: skip);

    test('ignore les tags qui ne sont pas des versions', () {
      git(['tag', 'v1.2.0']);
      git(['tag', 'tvos-20261113-1']);
      git(['tag', 'build/tvos/pas-une-version']);
      expect(version(['release', 'test']), '1.2.1');
    }, skip: skip);

    test('sans aucun tag, ouvre la 0.0.1', () {
      expect(version(['release', 'test']), '0.0.1');
    }, skip: skip);
  });

  group('une plateforme publiée seule', () {
    test('ouvre une version au-dessus de la dernière publication globale', () {
      // Jamais celle du tag : App Store Connect ferme une version dès
      // qu'elle est approuvée, et refuse alors tout nouveau build.
      git(['tag', 'v1.2.0']);
      expect(version(['platform', 'tvos']), '1.2.1');
    }, skip: skip);

    test('reste sur sa version tant qu’aucune publication globale n’est passée',
        () {
      git(['tag', 'v1.2.0']);
      git(['tag', 'build/tvos/1.2.1']);
      expect(version(['platform', 'tvos']), '1.2.1');
      // Une autre plateforme n'hérite pas de la version de l'Apple TV.
      expect(version(['platform', 'ios']), '1.2.1');
    }, skip: skip);

    test('rouvre une version après la publication globale suivante', () {
      git(['tag', 'v1.2.0']);
      git(['tag', 'build/tvos/1.2.1']);
      git(['tag', 'v1.2.2']);
      expect(version(['platform', 'tvos']), '1.2.3');
    }, skip: skip);
  });

  group('la note d’une version envoyée', () {
    test('est un tag build/<plateforme>/<version>, poussé une seule fois', () {
      git(['tag', 'v1.2.0']);
      expect(run(['record', 'tvos', '1.2.1']).exitCode, 0);
      // Un second build de la même version ne casse rien.
      expect(run(['record', 'tvos', '1.2.1']).exitCode, 0);

      final pushed = Process.runSync(
              'git', ['ls-remote', '--tags', origin.path]).stdout as String;
      expect(pushed, contains('refs/tags/build/tvos/1.2.1'));
      expect(version(['release', 'test']), '1.2.2');
    }, skip: skip);

    test('refuse une plateforme ou une version mal écrite', () {
      expect(run(['record', 'Apple TV', '1.2.1']).exitCode, isNot(0));
      expect(run(['record', 'tvos', '1.2']).exitCode, isNot(0));
      expect(run(['release', 'beta']).exitCode, isNot(0));
    }, skip: skip);
  });

  group('les workflows passent par ce calcul', () {
    test('release.yml ne recalcule pas la version de son côté', () {
      final workflow = File(_release).readAsStringSync();
      expect(workflow, contains('scripts/ci/resolve-version.sh release'),
          reason: 'Recalculée à partir du seul dernier tag vX.Y.Z, la '
              'version d’une publication globale retombe sur celle d’une '
              'Apple TV sortie seule ($_release).');
    });

    test('tvos.yml calcule sa version puis la note', () {
      final workflow = File(_tvos).readAsStringSync();
      expect(workflow, contains('scripts/ci/resolve-version.sh platform tvos'));
      expect(workflow, contains('scripts/ci/resolve-version.sh record tvos'),
          reason: 'Sans la note, release.yml ne sait pas que l’Apple TV est '
              'déjà à cette version ($_tvos).');
      expect(workflow, contains('contents: write'),
          reason: 'Pousser le tag build/tvos/X.Y.Z demande le droit '
              'd’écriture sur le dépôt ($_tvos).');
    });
  });
}
