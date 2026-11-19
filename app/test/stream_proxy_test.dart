import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/services/dns_warmup_io.dart';
import 'package:onyx/services/stream_proxy_io.dart';

/// Un serveur d'écho : ce qu'il reçoit, il le renvoie.
Future<ServerSocket> _echo() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) => s.listen(s.add, onDone: s.close));
  return server;
}

/// Un relais sur un port local, servi par [StreamProxy.serve].
Future<ServerSocket> _proxy(
    {Future<Socket> Function(String host, int port)? connect}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((c) => StreamProxy.serve(c, connect: connect));
  return server;
}

/// Ouvre un tunnel vers [target] et rend la réponse du relais puis l'écho de
/// [payload].
Future<String> _through(
    ServerSocket proxy, String target, String payload) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, proxy.port);
  final received = StringBuffer();
  final done = Completer<void>();
  socket.listen((d) => received.write(latin1.decode(d)), onDone: done.complete);
  socket
      .add(latin1.encode('CONNECT $target HTTP/1.1\r\nHost: $target\r\n\r\n'));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  socket.add(latin1.encode(payload));
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await socket.close();
  await done.future.timeout(const Duration(seconds: 5));
  return received.toString();
}

void main() {
  group('parseConnect', () {
    test('reads the host and port of a tunnel request', () {
      expect(StreamProxy.parseConnect('CONNECT player.yonix.me:443 HTTP/1.1'),
          (host: 'player.yonix.me', port: 443));
      expect(StreamProxy.parseConnect('CONNECT [2606:4700::1]:443 HTTP/1.1'),
          (host: '2606:4700::1', port: 443));
    });

    test('refuses anything that is not a tunnel', () {
      expect(StreamProxy.parseConnect('GET http://x/ HTTP/1.1'), isNull);
      expect(StreamProxy.parseConnect('CONNECT nohost HTTP/1.1'), isNull);
      expect(StreamProxy.parseConnect('CONNECT host:99999 HTTP/1.1'), isNull);
    });
  });

  test('tunnels bytes both ways once the CONNECT is answered', () async {
    final echo = await _echo();
    final proxy = await _proxy(
        connect: (_, __) =>
            Socket.connect(InternetAddress.loopbackIPv4, echo.port));
    final reply = await _through(proxy, 'server.test:443', 'chiffré');
    expect(reply, startsWith('HTTP/1.1 200 Connection established\r\n\r\n'));
    expect(
        reply, endsWith('chiffré'.codeUnits.map(String.fromCharCode).join()));
    await proxy.close();
    await echo.close();
  });

  test('connects to the last known address, never asking the system DNS',
      () async {
    final echo = await _echo();
    // Un nom qu'aucun DNS ne connaît : seule l'adresse gardée peut servir.
    DnsWarmup.rememberForTest('onyx.invalid', [InternetAddress.loopbackIPv4]);
    final proxy = await _proxy();
    final reply = await _through(proxy, 'onyx.invalid:${echo.port}', 'ok');
    expect(reply, startsWith('HTTP/1.1 200'));
    expect(reply, endsWith('ok'));
    await proxy.close();
    await echo.close();
  });

  test(
      'the relay mpv is given runs off the UI isolate and still knows the '
      'last address of the host', () async {
    final echo = await _echo();
    // Seule l'adresse transmise par routeFor peut servir : le relais tourne
    // dans un autre isolate, où DnsWarmup n'a rien résolu.
    DnsWarmup.rememberForTest('relay.invalid', [InternetAddress.loopbackIPv4]);
    StreamProxy.resetForTest();
    final route =
        await StreamProxy.routeFor('https://relay.invalid:${echo.port}/stream');
    expect(route, startsWith('http://127.0.0.1:'));
    // Une adresse morte dans l'isolate de l'interface : un relais qui
    // tournerait encore ici s'y connecterait et répondrait 502.
    DnsWarmup.rememberForTest('relay.invalid', [InternetAddress('192.0.2.1')]);
    final port = Uri.parse(route).port;
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final received = StringBuffer();
    final done = Completer<void>();
    socket.listen((d) => received.write(latin1.decode(d)),
        onDone: done.complete);
    socket.add(latin1.encode(
        'CONNECT relay.invalid:${echo.port} HTTP/1.1\r\n\r\n'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    socket.add(latin1.encode('isolé'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await socket.close();
    await done.future.timeout(const Duration(seconds: 5));
    expect(received.toString(), startsWith('HTTP/1.1 200'));
    expect(received.toString(), endsWith(latin1.decode(latin1.encode('isolé'))));
    await echo.close();
  });

  test('answers 502 when the server cannot be reached', () async {
    final proxy = await _proxy(
        connect: (_, __) =>
            Future<Socket>.error(const SocketException('down')));
    final reply = await _through(proxy, 'server.test:443', '');
    expect(reply, startsWith('HTTP/1.1 502'));
    await proxy.close();
  });

  test('answers 400 to a request that is not a tunnel', () async {
    final proxy = await _proxy();
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, proxy.port);
    socket.add(latin1.encode('GET http://x/ HTTP/1.1\r\n\r\n'));
    final reply = await socket.map(latin1.decode).join();
    expect(reply, startsWith('HTTP/1.1 400'));
    await proxy.close();
  });

  test('IPv4 first: announced IPv6 often has no route from the device', () {
    final v6 = InternetAddress('2606:4700::1');
    final v4 = InternetAddress('104.21.59.219');
    expect(DnsWarmup.preferIpv4([v6, v4]), [v4, v6]);
  });
}
