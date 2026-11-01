import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
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
}
