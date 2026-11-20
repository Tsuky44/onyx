import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// La sortie vidéo de mpv quand il dessine dans une `MpvHostView`.
///
/// Les options passent par ici dans l'ordre où elles sont demandées, et
/// chacune n'est rendue qu'une fois que mpv l'a appliquée : c'est ce qui
/// permet de libérer une vue en sachant que mpv n'y dessine plus.
///
/// Chaque appel part d'un isolate à part. Changer `vo` reconstruit la sortie
/// vidéo, et sur macOS cette reconstruction attend le thread principal. Si le
/// thread de l'interface restait bloqué dessus, un redimensionnement de
/// fenêtre au même moment — qui fait attendre le thread principal sur celui de
/// l'interface — suffirait à tout figer.
final class MpvNativeOutput {
  MpvNativeOutput({required this.libmpvPath, required this.mpvHandle});

  /// Le libmpv que media_kit a chargé : même bibliothèque, même instance.
  final String libmpvPath;

  /// L'adresse du `mpv_handle` (`Player.handle` de media_kit).
  final int mpvHandle;

  int? _attachedView;
  Future<void> _queue = Future.value();

  /// Fait dessiner mpv dans cette vue. `wid` avant `vo` : mpv ne lit `wid`
  /// qu'à la création de sa sortie vidéo.
  Future<void> attach(int viewHandle) => _enqueue(() async {
        await _set('wid', '$viewHandle');
        await _set('vo', 'gpu-next');
        _attachedView = viewHandle;
      });

  /// Reprend la vue à mpv s'il y dessine encore. Une vue déjà remplacée par
  /// une autre entre-temps n'est pas touchée.
  Future<void> detach(int viewHandle) => _enqueue(() async {
        if (_attachedView != viewHandle) return;
        await _set('vo', 'null');
        _attachedView = null;
      });

  Future<void> setProperty(String name, String value) =>
      _enqueue(() => _set(name, value));

  /// Lit [names] d'un seul appel, depuis un isolate à part ; null pour une
  /// propriété que mpv n'a pas.
  ///
  /// L'API de mpv est sûre d'un thread à l'autre, mais chaque lecture attend
  /// que le cœur de mpv soit libre. Faite depuis le thread de l'interface —
  /// ce que fait `getProperty` de media_kit —, une rafale de relevés pendant
  /// un seek ou un remplissage du cache y retenait les images de Flutter.
  /// Pas dans la file des options : une lecture n'a pas à attendre qu'une
  /// sortie vidéo se reconstruise.
  Future<Map<String, String?>> getProperties(List<String> names) {
    final library = libmpvPath;
    final handle = mpvHandle;
    final wanted = List<String>.of(names);
    return Isolate.run(() => _getPropertyStrings(library, handle, wanted));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.catchError((Object error) {
      debugPrint('MpvNativeOutput: $error');
    });
    return result;
  }

  Future<void> _set(String name, String value) async {
    final library = libmpvPath;
    final handle = mpvHandle;
    final code = await Isolate.run(
      () => _setPropertyString(library, handle, name, value),
    );
    if (code < 0) {
      throw StateError('mpv a refusé $name=$value (erreur $code)');
    }
  }
}

Map<String, String?> _getPropertyStrings(
  String libmpvPath,
  int handle,
  List<String> names,
) {
  final library = DynamicLibrary.open(libmpvPath);
  final getProperty = library.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>(
    'mpv_get_property_string',
  );
  final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('mpv_free');
  final mpv = Pointer<Void>.fromAddress(handle);
  final values = <String, String?>{};
  for (final name in names) {
    final nativeName = name.toNativeUtf8();
    try {
      final value = getProperty(mpv, nativeName);
      if (value == nullptr) {
        values[name] = null;
      } else {
        values[name] = value.toDartString();
        free(value.cast());
      }
    } finally {
      malloc.free(nativeName);
    }
  }
  return values;
}

int _setPropertyString(
  String libmpvPath,
  int handle,
  String name,
  String value,
) {
  final setProperty = DynamicLibrary.open(libmpvPath).lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>(
    'mpv_set_property_string',
  );
  final nativeName = name.toNativeUtf8();
  final nativeValue = value.toNativeUtf8();
  try {
    return setProperty(Pointer.fromAddress(handle), nativeName, nativeValue);
  } finally {
    malloc.free(nativeName);
    malloc.free(nativeValue);
  }
}
