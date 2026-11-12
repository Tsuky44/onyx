import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/my_request.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/services/api_client.dart';

/// L'onglet Demandes n'existe que si le serveur a un compagnon réglé : sans
/// MediaHub, le serveur répond 503 et rien ne pourrait être demandé.

class _Api extends ApiClient {
  _Api(this.status);
  int? status;
  int calls = 0;

  @override
  Future<RequestAccess> getRequestAccess() async {
    calls++;
    final code = status;
    if (code == null) return RequestAccess.basic;
    final options = RequestOptions(path: '/api/requests/access');
    throw DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: code),
    );
  }
}

Future<bool> _settle(MediaRequestsProvider provider) async {
  provider.companionConfigured;
  await pumpEventQueue();
  return provider.companionConfigured;
}

void main() {
  test('un serveur sans MediaHub (503) retire les demandes', () async {
    final provider = MediaRequestsProvider(_Api(503));
    expect(await _settle(provider), isFalse);
  });

  test('un compagnon réglé garde les demandes', () async {
    final provider = MediaRequestsProvider(_Api(null));
    expect(await _settle(provider), isTrue);
  });

  test('une panne passagère (502) ne retire pas les demandes', () async {
    final provider = MediaRequestsProvider(_Api(502));
    expect(await _settle(provider), isTrue);
  });

  test('régler MediaHub fait revenir les demandes', () async {
    final api = _Api(503);
    final provider = MediaRequestsProvider(api);
    expect(await _settle(provider), isFalse);
    api.status = null;
    await provider.recheckCompanion();
    expect(provider.companionConfigured, isTrue);
  });

  test('changer de serveur relit le compagnon', () async {
    final api = _Api(503);
    final provider = MediaRequestsProvider(api);
    expect(await _settle(provider), isFalse);
    api.status = null;
    provider.reset();
    expect(await _settle(provider), isTrue);
    expect(api.calls, 2);
  });
}
