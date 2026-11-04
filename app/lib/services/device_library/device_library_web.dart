/// Stub web de la bibliothèque de l'appareil — voir `device_library.dart`.
library;

import 'package:flutter/foundation.dart';

import '../../models/device_video.dart';

/// Même surface que la version native, vide : [isSupported] est faux.
class DeviceLibrary extends ChangeNotifier {
  DeviceLibrary._();

  static final DeviceLibrary instance = DeviceLibrary._();

  bool get isSupported => false;
  bool get canPickFolders => false;
  bool get canImportFiles => false;
  bool get isScanning => false;
  String? get appFolder => null;
  List<String> get folders => const [];
  List<DeviceVideo> get videos => const [];

  Future<void> initialize() async {}
  Future<void> rescan() async {}
  Future<bool> addFolder(String path) async => false;
  Future<void> removeFolder(String path) async {}
  Future<int> importFiles(List<String> paths) async => 0;
  Future<void> deleteVideo(DeviceVideo video) async {}

  String? pathFor(int id) => null;
  DeviceVideoProgress? progressFor(int id) => null;
  Future<void> recordProgress({
    required int id,
    required int positionSeconds,
    required int durationSeconds,
    required bool isFinished,
  }) async {}
}
