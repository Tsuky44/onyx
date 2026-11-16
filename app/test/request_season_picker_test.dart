import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/my_request.dart';
import 'package:onyx/screens/requests/widgets/request_season_picker_sheet.dart';

/// « Compléter » liste les saisons pas encore demandées et n'envoie que celles
/// qu'on coche : la saison 1 déjà là n'y figure pas.
RequestSeason _season(int number, RequestMediaStatus status) => RequestSeason(
      number: number,
      name: '',
      episodeCount: 8,
      posterPath: null,
      status: status,
    );

void main() {
  testWidgets('seules les saisons cochées partent, la saison là est absente',
      (tester) async {
    final details = RequestMediaDetails(
      id: 1,
      mediaType: RequestMediaType.tv,
      title: 'Série',
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: null,
      rating: 0,
      status: RequestMediaStatus.partial,
      runtime: null,
      genres: const [],
      seasons: [
        _season(1, RequestMediaStatus.available),
        _season(2, RequestMediaStatus.unknown),
        _season(3, RequestMediaStatus.unknown),
      ],
    );
    List<int>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await RequestSeasonPickerSheet.show(context, details),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.text('Saison 3'));
    await tester.pump();
    await tester.tap(find.text('Demander (1)'));
    await tester.pumpAndSettle();
    expect(result, [3]);
  });

  testWidgets('sans saison cochée, Demander est inactif et rien ne part',
      (tester) async {
    final details = RequestMediaDetails(
      id: 1,
      mediaType: RequestMediaType.tv,
      title: 'Série',
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: null,
      rating: 0,
      status: RequestMediaStatus.partial,
      runtime: null,
      genres: const [],
      seasons: [_season(1, RequestMediaStatus.unknown)],
    );
    var opened = false;
    List<int>? result = const [-1];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            opened = true;
            result = await RequestSeasonPickerSheet.show(context, details);
          },
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);

    await tester.tap(find.text('Demander (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Compléter la demande'), findsOneWidget);
    expect(result, [-1]);
  });

  testWidgets(
      'une série vierge, quand MediaHub laisse choisir, liste toutes ses saisons',
      (tester) async {
    final details = RequestMediaDetails(
      id: 1,
      mediaType: RequestMediaType.tv,
      title: 'Série',
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: null,
      rating: 0,
      status: RequestMediaStatus.unknown,
      runtime: null,
      genres: const [],
      seasons: [
        _season(1, RequestMediaStatus.unknown),
        _season(2, RequestMediaStatus.unknown),
      ],
    );
    List<int>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await RequestSeasonPickerSheet.show(
              context, details,
              completing: false),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.text('Choisir les saisons'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.text('Saison 1'));
    await tester.pump();
    await tester.tap(find.text('Demander (1)'));
    await tester.pumpAndSettle();
    expect(result, [1]);
  });

  test('le choix des saisons suit le réglage de MediaHub relayé par Onyx', () {
    expect(RequestAccess.fromJson({'seasonChoice': true}).seasonChoice, isTrue);
    expect(
        RequestAccess.fromJson({'seasonChoice': false}).seasonChoice, isFalse);
    // Un serveur d'avant le champ garde l'ancien geste : toutes les saisons.
    expect(RequestAccess.fromJson(const {}).seasonChoice, isFalse);
    expect(RequestAccess.basic.seasonChoice, isFalse);
  });
}
