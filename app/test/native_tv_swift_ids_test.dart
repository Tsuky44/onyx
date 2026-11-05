@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/playback/native_tv_presenter.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';

/// Les identifiants que Swift écrit en dur et que Dart attend dans ses
/// événements ou ses panneaux.
///
/// Le contrat Pigeon ne porte que des chaînes : un identifiant renommé d'un
/// seul côté compile des deux côtés, et la proposition de l'épisode suivant,
/// ou le panneau Stats, ne répondrait plus que sur une vraie Apple TV, que ni
/// la CI ni le simulateur ne remplacent. Les deux lots de la parité ont été
/// écrits en parallèle : ce test tient leur accord.
const _sources =
    '../packages/onyx_player_apple/darwin/onyx_player_apple/Sources/onyx_player_apple';

String _swift(String file) =>
    File('$_sources/$file').readAsStringSync().replaceAll('\r\n', '\n');

/// La valeur de `static let <name> = "<valeur>"`, ou null.
String? _staticString(String source, String name) =>
    RegExp('static let $name = "([^"]*)"').firstMatch(source)?.group(1);

void main() {
  test('« Lire » et « Plus tard » de la proposition sont des actions de Dart',
      () {
    final source = _swift('NativeNextUpProposalController.swift');
    expect(_staticString(source, 'playActionId'), NativeTvIds.nextEpisode);
    expect(_staticString(source, 'laterActionId'), NativeTvIds.cancelAutoPlay);
    expect(
      nativeTvIntentOf(OnyxAppleNativeEvent(
        playerId: 1,
        kind: OnyxAppleNativeEventKind.action,
        actionId: _staticString(source, 'laterActionId'),
      )),
      isA<NativeTvCancelAutoPlay>(),
    );
  });

  test('Swift remplit les mesures que le panneau Stats de Dart liste', () {
    final source = _swift('NativeInfoPanelController.swift');
    expect(_staticString(source, 'statsPanelId'), NativeTvIds.statsPanel);
    final filled = {
      for (final match
          in RegExp(r'values\["([A-Za-z]+)"\] =').allMatches(source))
        match.group(1)!,
    };
    expect(filled, NativeTvPanels.statsRows.toSet(),
        reason: 'Une mesure listée par Dart sans valeur Swift reste à « — » ; '
            'une valeur Swift sans ligne Dart ne s’affiche jamais.');
  });
}
