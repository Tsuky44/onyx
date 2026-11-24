import 'dart:async';

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/watch_party_invite.dart';
import 'package:onyx/screens/player/hooks/use_player_invite.dart';
import 'package:onyx/screens/player/widgets/player_invite_overlay.dart';
import 'package:onyx/screens/player/widgets/tabs/player_watch_party_invitees.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/watch_party_invites.dart';
import 'package:onyx/widgets/global/watch_party_invite_card.dart';

/// Inviter à une séance les personnes qui ont Onyx ouvert (ADR-0148).

Map<String, dynamic> _invite(String id, {String from = 'alex'}) => {
      'id': id,
      'code': 'ABC123',
      'from': from,
      'media_id': 7,
      'media': {'id': 7, 'type': 'movie', 'title': 'Dune'},
      'expires_in_seconds': 120,
    };

/// Une boîte d'invitations à la main : chaque attente rend la prochaine
/// réponse poussée par le test, et reste en suspens tant qu'il n'y en a pas.
class _InboxApi extends ApiClient {
  _InboxApi({this.supported = true});

  final bool supported;
  final List<int> polledSince = [];
  final List<String> declined = [];
  final _replies = StreamController<WatchPartyInvites>();
  late final StreamIterator<WatchPartyInvites> _next =
      StreamIterator(_replies.stream);

  void push(int version, List<Map<String, dynamic>> invites) => _replies.add(
      WatchPartyInvites.fromJson({'version': version, 'invites': invites}));

  @override
  Future<bool> supportsWatchPartyInvites() async => supported;

  @override
  Future<WatchPartyInvites> pollWatchPartyInvites({
    required int since,
    CancelToken? cancelToken,
  }) async {
    polledSince.add(since);
    if (!await _next.moveNext()) throw StateError('fermé');
    return _next.current;
  }

  @override
  Future<void> declineWatchPartyInvite(String id) async => declined.add(id);
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('la boîte d’invitations', () {
    test('montre l’invitation qui arrive, puis attend la suivante', () async {
      final api = _InboxApi();
      final inbox =
          WatchPartyInviteInbox(api: () => api, accountKey: () => 'a');
      inbox.refresh();
      await _settle();
      expect(api.polledSince, [0]);
      expect(inbox.current, isNull);

      api.push(4, [_invite('i1')]);
      await _settle();
      expect(inbox.current?.from, 'alex');
      expect(api.polledSince, [0, 4],
          reason: 'l’attente suivante part du numéro reçu');
      inbox.dispose();
    });

    test(
        'vue dans le lecteur, elle ne revient pas ; refusée, le serveur le '
        'sait', () async {
      final api = _InboxApi();
      final inbox =
          WatchPartyInviteInbox(api: () => api, accountKey: () => 'a');
      inbox.refresh();
      await _settle();
      api.push(2, [_invite('i1'), _invite('i2', from: 'sam')]);
      await _settle();

      inbox.markSeen(inbox.current!);
      expect(inbox.current?.id, 'i2',
          reason: 'la seconde invitation attendait derrière la première');
      expect(api.declined, isEmpty, reason: 'vue n’est pas refusée');

      inbox.decline(inbox.current!);
      await _settle();
      expect(inbox.current, isNull);
      expect(api.declined, ['i2']);
      inbox.dispose();
    });

    test('un serveur sans invitations n’est pas sondé', () async {
      final api = _InboxApi(supported: false);
      final inbox =
          WatchPartyInviteInbox(api: () => api, accountKey: () => 'a');
      inbox.refresh();
      await _settle();
      expect(api.polledSince, isEmpty);
      inbox.dispose();
    });

    test('hors connexion, rien n’attend', () async {
      final api = _InboxApi();
      final inbox =
          WatchPartyInviteInbox(api: () => api, accountKey: () => null);
      inbox.refresh();
      await _settle();
      expect(api.polledSince, isEmpty);
      inbox.dispose();
    });
  });

  group('la carte d’invitation', () {
    testWidgets('dit qui invite à quoi, et répond des deux boutons',
        (tester) async {
      var accepted = 0;
      var declined = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: WatchPartyInviteCard(
              invite: WatchPartyInvite.fromJson(_invite('i1')),
              serverBaseUrl: null,
              onAccept: () => accepted++,
              onDecline: () => declined++,
            ),
          ),
        ),
      ));

      expect(find.text('alex vous invite'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('watch-party-invite-accept')));
      await tester
          .tap(find.byKey(const ValueKey('watch-party-invite-decline')));
      expect((accepted, declined), (1, 1));
    });
  });

  group('pendant un film', () {
    testWidgets('la carte s’en va d’elle-même au bout de dix secondes',
        (tester) async {
      var timedOut = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerInviteOverlay(
            invite: WatchPartyInvite.fromJson(_invite('i1')),
            serverBaseUrl: null,
            joining: false,
            onAccept: () {},
            onDecline: () {},
            onTimeout: () => timedOut++,
          ),
        ),
      ));

      await tester.pump(const Duration(seconds: 9));
      expect(timedOut, 0);
      await tester.pump(const Duration(seconds: 1, milliseconds: 50));
      expect(timedOut, 1);
    });

    test('ignorée par le temps, elle est vue ; Retour la refuse', () async {
      final api = _InboxApi();
      final inbox =
          WatchPartyInviteInbox(api: () => api, accountKey: () => 'a');
      inbox.refresh();
      await _settle();
      api.push(2, [_invite('i1'), _invite('i2', from: 'sam')]);
      await _settle();

      var focusRestored = 0;
      final watch = PlayerInviteWatch(
        join: (_) async {},
        isGone: () => false,
        restoreFocus: () => focusRestored++,
        showFailure: (_) {},
        inbox: inbox,
      )..listen();
      expect(watch.shown?.id, 'i1');

      watch.timeout();
      await _settle();
      expect(api.declined, isEmpty);
      expect(watch.shown?.id, 'i2', reason: 'la suivante prend sa place');

      expect(watch.back(), isTrue);
      await _settle();
      expect(api.declined, ['i2']);
      expect(watch.shown, isNull);
      expect(watch.back(), isFalse,
          reason: 'sans carte, Retour quitte le film');
      expect(focusRestored, 2);
      watch.dispose();
      inbox.dispose();
    });

    test('rejoindre passe par la séance du lecteur', () async {
      final api = _InboxApi();
      final inbox =
          WatchPartyInviteInbox(api: () => api, accountKey: () => 'a');
      inbox.refresh();
      await _settle();
      api.push(2, [_invite('i1')]);
      await _settle();

      final joined = <String>[];
      final watch = PlayerInviteWatch(
        join: (invite) async => joined.add(invite.code),
        isGone: () => false,
        restoreFocus: () {},
        showFailure: (_) {},
        inbox: inbox,
      )..listen();
      await watch.accept();
      expect(joined, ['ABC123']);
      expect(watch.shown, isNull);
      watch.dispose();
      inbox.dispose();
    });
  });

  group('l’onglet de la séance', () {
    testWidgets('liste qui a Onyx ouvert, et invite d’un bouton',
        (tester) async {
      final invited = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: PlayerWatchPartyInvitees(
            load: () async => const [
              WatchPartyInvitee(userId: 2, username: 'sam'),
              WatchPartyInvitee(
                userId: 3,
                username: 'lou',
                status: WatchPartyInviteStatus.declined,
              ),
            ],
            invite: (id) async => invited.add(id),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('sam'), findsOneWidget);
      expect(find.text('A refusé'), findsOneWidget);
      expect(find.text('Réinviter'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('player-party-invite-2')));
      await tester.pump();
      expect(invited, [2]);
      expect(find.text('Envoyée'), findsOneWidget);

      // Démonté, l'onglet ne relit plus la liste.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('personne d’autre en ligne : le code reste le moyen',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerWatchPartyInvitees(
            load: () async => const [],
            invite: (_) async {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Personne d’autre n’a Onyx ouvert. Partagez le code.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
