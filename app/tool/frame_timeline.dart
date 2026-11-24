// Relevé des temps d'image d'un build profile, pour comparer deux versions de
// Flutter à l'identique (ADR-0167). Pas livré : un script `dart` qui parle au
// VM service de l'app par WebSocket, sans dépendance.
//
// L'app se lance avec un port fixe et sans code d'accès, par les variables
// que l'embedder Windows lit hors release :
//
//   $env:FLUTTER_ENGINE_SWITCHES = 2
//   $env:FLUTTER_ENGINE_SWITCH_1 = 'vm-service-port=8181'
//   $env:FLUTTER_ENGINE_SWITCH_2 = 'disable-service-auth-codes'
//   build\windows\x64\runner\Profile\app.exe
//
// Puis, pour chaque geste :
//
//   dart tool/frame_timeline.dart record accueil-1 mesures.jsonl 14
//   … le geste dans l'app pendant ces 14 secondes …
//
// La timeline du VM est un tampon circulaire : lue une seule fois à la fin,
// elle ne garde que les ~280 dernières images. Le relevé vide donc le tampon,
// le relit chaque seconde et dédoublonne les événements. À la fin, il
// calcule les durées de construction (fil UI) et de rastérisation (fil
// raster) de chaque image et ajoute une ligne JSON au fichier donné. Les noms
// suivis sont ceux du moteur ; `topEventsMs` liste les plus coûteux pour
// qu'un renommage d'une version à l'autre se voie au lieu d'un zéro.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Les noms d'une même étape sont imbriqués (Draw contient DoDraw) : seul le
// premier présent compte, sinon chaque image serait comptée deux fois.
const _uiEvents = ['Animator::BeginFrame'];
const _rasterEvents = ['GPURasterizer::Draw', 'Rasterizer::DoDraw'];
const _budgetMicros = 16667;
const _pollEvery = Duration(seconds: 1);

Future<void> main(List<String> args) async {
  final port = Platform.environment['ONYX_VM_PORT'] ?? '8181';
  final seconds = args.length == 4 ? int.tryParse(args[3]) : null;
  if (args.isEmpty || args.first != 'record' || seconds == null) {
    stderr.writeln('usage: frame_timeline.dart record <libellé> <fichier.jsonl> <secondes>');
    exitCode = 64;
    return;
  }
  final vm = await _Vm.connect('ws://127.0.0.1:$port/ws');
  try {
    await vm.call('setVMTimelineFlags', {
      'recordedStreams': ['Dart', 'Embedder', 'GC'],
    });
    await vm.call('clearVMTimeline');
    final seen = <String>{};
    final events = <Map<String, dynamic>>[];
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (true) {
      final timeline = await vm.call('getVMTimeline');
      for (final e in (timeline['traceEvents'] as List).cast<Map<String, dynamic>>()) {
        if (seen.add('${e['ph']}|${e['tid']}|${e['ts']}|${e['name']}')) events.add(e);
      }
      if (DateTime.now().isAfter(end)) break;
      await Future<void>.delayed(_pollEvery);
    }
    final summary = summarize(args[1], events);
    File(args[2]).writeAsStringSync('${jsonEncode(summary)}\n', mode: FileMode.append);
    stdout.writeln(jsonEncode(summary));
  } finally {
    await vm.close();
  }
}

Map<String, Object?> summarize(String label, List<Map<String, dynamic>> events) {
  // Les événements de métadonnées (noms des fils) n'ont pas d'horodatage.
  final timed = events.where((e) => e['ts'] is num && e['name'] is String).toList()
    ..sort((a, b) => (a['ts'] as num).compareTo(b['ts'] as num));
  final durations = <String, List<int>>{};
  final open = <String, List<int>>{};
  for (final e in timed) {
    final name = e['name'] as String;
    final ts = e['ts'] as num;
    final key = '${e['tid']}|$name';
    switch (e['ph']) {
      case 'X':
        durations.putIfAbsent(name, () => []).add((e['dur'] as num? ?? 0).toInt());
      case 'B':
        open.putIfAbsent(key, () => []).add(ts.toInt());
      case 'E':
        // Un événement récursif (Semantics.updateChildren…) ne compte qu'à
        // son niveau le plus externe, sinon son cumul se multiplie par sa
        // profondeur.
        final stack = open[key];
        if (stack != null && stack.isNotEmpty) {
          final start = stack.removeLast();
          if (stack.isEmpty) durations.putIfAbsent(name, () => []).add(ts.toInt() - start);
        }
    }
  }
  List<int> pick(List<String> names) => [
        ...?durations[names.firstWhere(durations.containsKey, orElse: () => '')],
      ];
  final totals = durations.entries
      .map((e) => MapEntry(e.key, e.value.fold<int>(0, (a, b) => a + b)))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {
    'label': label,
    'at': DateTime.now().toIso8601String(),
    'ui': _stats(pick(_uiEvents)),
    'raster': _stats(pick(_rasterEvents)),
    'topEventsMs': {
      for (final e in totals.take(12)) e.key: (e.value / 1000).toStringAsFixed(1),
    },
  };
}

Map<String, Object?> _stats(List<int> micros) {
  if (micros.isEmpty) return {'frames': 0};
  final sorted = [...micros]..sort();
  double ms(int us) => double.parse((us / 1000).toStringAsFixed(2));
  int at(double q) => sorted[((sorted.length - 1) * q).round()];
  return {
    'frames': sorted.length,
    'p50': ms(at(0.5)),
    'p90': ms(at(0.9)),
    'p99': ms(at(0.99)),
    'max': ms(sorted.last),
    'over16ms': sorted.where((d) => d > _budgetMicros).length,
  };
}

class _Vm {
  _Vm(this._socket) {
    _socket.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final pending = _pending.remove(msg['id']);
      if (pending == null) return; // notification d'un flux : non suivie ici
      if (msg['error'] != null) {
        pending.completeError(StateError('${msg['error']}'));
      } else {
        pending.complete(msg['result'] as Map<String, dynamic>);
      }
    });
  }

  static Future<_Vm> connect(String url) async => _Vm(await WebSocket.connect(url));

  final WebSocket _socket;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  var _next = 0;

  Future<Map<String, dynamic>> call(String method, [Map<String, Object?>? params]) {
    final id = '${_next++}';
    final done = Completer<Map<String, dynamic>>();
    _pending[id] = done;
    _socket.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params ?? {}}));
    return done.future;
  }

  Future<void> close() => _socket.close();
}
