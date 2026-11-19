import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../utils/app_platform.dart';
import 'dns_warmup_io.dart';

/// Un relais `CONNECT` sur la boucle locale, pour que mpv n'attende jamais le
/// DNS du système.
///
/// La libmpv de l'app ouvre ses flux avec libcurl, qui résout le nom au moment
/// d'ouvrir — sur le chemin de la première image — et sous Windows cette
/// résolution peut coûter 11 s (voir [DnsWarmup]). mpv n'a pas d'option pour
/// fixer l'adresse d'un nom, et forcer une adresse IP dans l'URL casse le TLS :
/// ni libcurl ni FFmpeg n'envoient alors le nom que Cloudflare attend (essayé :
/// `verifyhost` n'y change rien).
///
/// Derrière un proxy, en revanche, libcurl ne résout rien : il demande
/// `CONNECT hôte:443`, puis mène le TLS lui-même, de bout en bout, avec le bon
/// nom. Ce relais n'a qu'à ouvrir la connexion vers la dernière adresse connue
/// de l'hôte ([DnsWarmup.addressesFor]) et recopier les octets, chiffrés, dans
/// les deux sens. Mesuré sur la libmpv de l'app : 117 ms jusqu'au premier
/// démultiplexeur, contre 11,3 s en résolvant.
///
/// Le relais tourne dans son propre isolate, jamais dans celui de
/// l'interface : tout le film le traverse, et mpv remplit son cache par
/// rafales de plus de 150 Mbit/s. Dans l'isolate de l'interface, chaque
/// morceau recopié et le ramasse-miettes qui suivait retardaient les images
/// Flutter — interface saccadée, et image de la texture figée pendant que le
/// son continuait, sans que mpv compte une image perdue (journaux d'un
/// utilisateur Windows en HTTPS, ADR-0036).
///
/// Rien n'est déchiffré ni lu au-delà de la ligne `CONNECT`. Il n'écoute que
/// sur 127.0.0.1 : un programme local qui s'en servirait n'obtiendrait rien
/// qu'il ne puisse déjà faire lui-même.
abstract final class StreamProxy {
  static Future<_RelayIsolate?>? _relay;

  /// Les adresses que l'isolate de l'interface a transmises au relais. Dans
  /// l'isolate du relais, [DnsWarmup] est vide : il ne résout rien lui-même.
  static final Map<String, List<InternetAddress>> _known = {};

  /// Où vont les lignes de journal. Dans l'isolate du relais, vers celui de
  /// l'interface, seul à les verser dans le journal exportable.
  static void Function(String line) _log = _printLine;
  static void _printLine(String line) => debugPrint(line);

  /// La valeur de `http-proxy` pour ouvrir [url] : le relais pour un flux
  /// HTTPS sur desktop, une chaîne vide sinon (pas de proxy).
  ///
  /// HTTPS seulement : en HTTP, libcurl enverrait au proxy des requêtes
  /// entières à relayer plutôt qu'un tunnel, et les serveurs joints en HTTP
  /// sont ceux du réseau local, adressés par IP ou par un nom local. Desktop
  /// seulement : c'est là que le DNS lent a été constaté, et un relais local
  /// sur iOS devrait survivre aux suspensions de l'app.
  ///
  /// Transmet au relais la dernière adresse connue de l'hôte avant de rendre
  /// la main : mpv s'y connecte juste après.
  static Future<String> routeFor(String url) async {
    if (!AppPlatform.isDesktop) return '';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return '';
    final relay = await (_relay ??= _RelayIsolate.spawn());
    if (relay == null) return '';
    await relay.remember(uri.host, DnsWarmup.addressesFor(uri.host));
    return 'http://127.0.0.1:${relay.port}';
  }

  /// Le point d'entrée de l'isolate du relais.
  static Future<void> _run(SendPort ui) async {
    _log = ui.send;
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      // Sans relais, mpv résout lui-même : plus lent, jamais cassé.
      ui.send('StreamProxy: relais indisponible ($e) — résolution directe');
      return;
    }
    final commands = ReceivePort();
    commands.listen((message) {
      if (message case (String host, List<String> addresses, SendPort done)) {
        final key = host.toLowerCase();
        if (addresses.isEmpty) {
          _known.remove(key);
        } else {
          _known[key] = [for (final a in addresses) InternetAddress(a)];
        }
        done.send(true);
      }
    });
    server.listen((client) => unawaited(serve(client)));
    ui.send((server.port, commands.sendPort));
  }

  /// Sert un client : lit la ligne `CONNECT`, ouvre le tunnel, recopie.
  @visibleForTesting
  static Future<void> serve(
    Socket client, {
    Future<Socket> Function(String host, int port)? connect,
  }) async {
    final header = BytesBuilder(copy: false);
    final rest = StreamController<Uint8List>();
    var tunnelled = false;
    final headerRead = Completer<({String host, int port})?>();

    late final StreamSubscription<Uint8List> fromClient;
    fromClient = client.listen(
      (chunk) {
        if (tunnelled) {
          rest.add(chunk);
          return;
        }
        header.add(chunk);
        final bytes = header.toBytes();
        final end = _headerEnd(bytes);
        if (end < 0) {
          if (bytes.length > _maxHeader && !headerRead.isCompleted) {
            headerRead.complete(null);
          }
          return;
        }
        tunnelled = true;
        if (end < bytes.length) rest.add(Uint8List.sublistView(bytes, end));
        if (!headerRead.isCompleted) {
          headerRead
              .complete(parseConnect(latin1.decode(bytes.sublist(0, end))));
        }
      },
      onError: (_) {
        if (!headerRead.isCompleted) headerRead.complete(null);
        rest.close();
      },
      onDone: () {
        if (!headerRead.isCompleted) headerRead.complete(null);
        rest.close();
      },
      cancelOnError: true,
    );

    final target = await headerRead.future;
    if (target == null) {
      await fromClient.cancel();
      client.add(latin1.encode('HTTP/1.1 400 Bad Request\r\n\r\n'));
      await client.close().catchError((_) => client);
      return;
    }

    final Socket upstream;
    try {
      upstream = await (connect ?? _connect)(target.host, target.port);
    } catch (e) {
      _log('StreamProxy: ${target.host}:${target.port} injoignable: $e');
      await fromClient.cancel();
      client.add(latin1.encode('HTTP/1.1 502 Bad Gateway\r\n\r\n'));
      await client.close().catchError((_) => client);
      return;
    }

    client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
    // Vers le serveur : la poignée de main TLS et les requêtes, peu de chose.
    unawaited(upstream
        .addStream(rest.stream)
        .then((_) => upstream.close())
        .catchError((_) => upstream.destroy()));
    // Vers mpv : le film. `addStream` suspend la lecture du serveur tant que
    // mpv n'a pas repris ce qu'on lui a donné — la mémoire reste bornée.
    try {
      await client.addStream(upstream);
      await client.close();
    } catch (_) {
      client.destroy();
    } finally {
      upstream.destroy();
      await fromClient.cancel();
    }
  }

  static const _maxHeader = 8 * 1024;

  /// La position juste après `\r\n\r\n`, ou -1.
  static int _headerEnd(Uint8List bytes) {
    for (var i = 3; i < bytes.length; i++) {
      if (bytes[i] == 10 &&
          bytes[i - 1] == 13 &&
          bytes[i - 2] == 10 &&
          bytes[i - 3] == 13) {
        return i + 1;
      }
    }
    return -1;
  }

  /// `CONNECT hôte:port HTTP/1.1` → l'hôte et le port ; null pour toute autre
  /// requête. Les crochets d'une adresse IPv6 sont retirés.
  @visibleForTesting
  static ({String host, int port})? parseConnect(String header) {
    final line = header.split('\r\n').first.split(' ');
    if (line.length != 3 || line[0] != 'CONNECT') return null;
    final target = line[1];
    final colon = target.lastIndexOf(':');
    if (colon <= 0) return null;
    final port = int.tryParse(target.substring(colon + 1));
    var host = target.substring(0, colon);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (port == null || port <= 0 || port > 65535 || host.isEmpty) return null;
    return (host: host, port: port);
  }

  /// Les adresses connues d'abord, le nom en dernier recours : une adresse
  /// périmée qui ne répond plus coûte trois secondes, pas une lecture.
  static Future<Socket> _connect(String host, int port) async {
    final known = _known[host.toLowerCase()] ?? DnsWarmup.addressesFor(host);
    for (final address in known ?? const <InternetAddress>[]) {
      try {
        return await Socket.connect(address, port,
            timeout: const Duration(seconds: 3));
      } catch (_) {
        // Adresse périmée : on essaie la suivante, puis le nom.
      }
    }
    return Socket.connect(host, port, timeout: const Duration(seconds: 30));
  }

  /// Oublie le relais lancé, pour qu'un test en démarre un neuf.
  @visibleForTesting
  static void resetForTest() => _relay = null;
}

/// L'isolate du relais, vu de celui de l'interface.
final class _RelayIsolate {
  _RelayIsolate._(this.port, this._commands);

  /// Le port local où le relais écoute.
  final int port;
  final SendPort _commands;

  /// Lance l'isolate et attend son port ; null s'il n'a pas pu écouter.
  static Future<_RelayIsolate?> spawn() async {
    final inbox = ReceivePort();
    final ready = Completer<_RelayIsolate?>();
    inbox.listen((message) {
      switch (message) {
        case (int port, SendPort commands):
          ready.complete(_RelayIsolate._(port, commands));
        case String line:
          debugPrint(line);
        default:
          // L'isolate s'est arrêté (`onExit`). Avant d'être prêt : pas de
          // relais. Après : le prochain flux en relance un, au lieu de
          // confier mpv à un port où plus personne n'écoute.
          inbox.close();
          if (ready.isCompleted) {
            StreamProxy._relay = null;
          } else {
            ready.complete(null);
          }
      }
    });
    try {
      await Isolate.spawn(StreamProxy._run, inbox.sendPort,
          onExit: inbox.sendPort,
          errorsAreFatal: false,
          debugName: 'StreamProxy');
    } catch (e) {
      inbox.close();
      debugPrint('StreamProxy: isolate impossible ($e) — résolution directe');
      return null;
    }
    return ready.future;
  }

  /// Donne au relais les adresses de [host]. Une liste vide ou absente
  /// l'oublie : le relais résoudra le nom lui-même.
  Future<void> remember(String host, List<InternetAddress>? addresses) async {
    final done = ReceivePort();
    try {
      _commands.send((
        host,
        [for (final a in addresses ?? const <InternetAddress>[]) a.address],
        done.sendPort,
      ));
      await done.first.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // Un relais qui ne répond pas résoudra le nom lui-même : plus lent,
      // pas cassé. Son arrêt, lui, est vu par `onExit`.
    } finally {
      done.close();
    }
  }
}
