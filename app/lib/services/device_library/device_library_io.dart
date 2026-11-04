import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/device_video.dart';
import '../../tv/tv_mode.dart';
import '../../utils/app_platform.dart';
import 'device_video_access.dart';

/// Les vidéos personnelles de l'appareil : des dossiers suivis, ce qu'on y
/// trouve, et où on en est de chacune. Aucun serveur n'est en jeu — c'est ce
/// qui rend l'app utile dès l'installation (ADR-0104).
///
/// Seuls les chemins des dossiers et l'avancement sont écrits sur disque. La
/// liste des vidéos est refaite à chaque scan : un fichier déplacé ou effacé
/// hors de l'app disparaît au scan suivant, sans manifeste à réconcilier.
class DeviceLibrary extends ChangeNotifier {
  DeviceLibrary({Future<Directory> Function()? stateDirectory,
      Future<Directory?> Function()? appFolder})
      : _stateDirectory = stateDirectory ?? getApplicationSupportDirectory,
        _resolveAppFolder = appFolder ?? _defaultAppFolder;

  static final DeviceLibrary instance = DeviceLibrary();

  /// Au-delà, le scan s'arrête : un disque entier choisi par erreur ne doit
  /// pas geler l'écran ni remplir la mémoire.
  static const int maxFiles = 20000;

  final Future<Directory> Function() _stateDirectory;
  final Future<Directory?> Function() _resolveAppFolder;

  final List<String> _folders = [];
  final Map<String, DeviceVideoProgress> _progress = {};
  List<DeviceVideo> _videos = const [];
  final Map<int, DeviceVideo> _byId = {};
  final List<StreamSubscription<FileSystemEvent>> _watches = [];
  Timer? _watchDebounce;
  String? _appFolder;
  bool _ready = false;
  bool _scanning = false;
  bool _rescanQueued = false;
  Future<void>? _initializing;

  /// Ni le web (stub), ni l'Apple TV, qui n'a pas de système de fichiers à
  /// montrer, ni un téléviseur Android, dont l'écran n'a pas été pensé pour la
  /// télécommande.
  bool get isSupported => !AppPlatform.isTvOS && !TvMode.isTv;

  /// iOS ne rend pas un dossier choisi lisible d'un lancement à l'autre sans
  /// signets de sécurité ; le dossier Documents de l'app, ouvert dans
  /// l'app Fichiers et le Finder, en tient lieu.
  bool get canPickFolders => isSupported && !AppPlatform.isIOS;

  bool get canImportFiles => isSupported && AppPlatform.isIOS;

  bool get isScanning => _scanning;

  /// Le dossier propre à l'app, suivi d'office quand il existe (iOS).
  String? get appFolder => _appFolder;

  List<String> get folders => List.unmodifiable(_folders);
  List<DeviceVideo> get videos => _videos;

  static Future<Directory?> _defaultAppFolder() async {
    if (!AppPlatform.isIOS) return null;
    return getApplicationDocumentsDirectory();
  }

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!isSupported) return;
    try {
      final app = await _resolveAppFolder();
      _appFolder = app?.path;
      final file = await _stateFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          for (final folder in (raw['folders'] as List?) ?? const []) {
            if (folder is String && !_folders.contains(folder)) {
              _folders.add(folder);
            }
          }
          final progress = raw['progress'];
          if (progress is Map<String, dynamic>) {
            progress.forEach((path, value) {
              if (value is Map<String, dynamic>) {
                _progress[path] = DeviceVideoProgress.fromJson(value);
              }
            });
          }
        }
      }
    } catch (e) {
      // Un état illisible repart de zéro : les fichiers eux-mêmes sont
      // intacts, seuls les dossiers suivis sont à rechoisir.
      debugPrint('DeviceLibrary: état illisible, repart à vide: $e');
    }
    _ready = true;
    _rewatch();
    await rescan();
  }

  Future<File> _stateFile() async {
    final dir = await _stateDirectory();
    return File(p.join(dir.path, 'device_library.json'));
  }

  Future<void> _save() async {
    try {
      final file = await _stateFile();
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'folders': _folders,
        'progress': {
          for (final entry in _progress.entries) entry.key: entry.value.toJson(),
        },
      }));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('DeviceLibrary: écriture de l’état impossible: $e');
    }
  }

  List<String> get _scannedRoots => [
        if (_appFolder != null) _appFolder!,
        ..._folders,
      ];

  /// Refait la liste. Un scan demandé pendant un autre est rejoué après lui,
  /// pour que l'ajout d'un dossier en cours de scan ne soit pas perdu.
  Future<void> rescan() async {
    if (!_ready) return initialize();
    if (_scanning) {
      _rescanQueued = true;
      return;
    }
    _scanning = true;
    notifyListeners();
    try {
      do {
        _rescanQueued = false;
        final found = <DeviceVideo>[];
        for (final root in _scannedRoots) {
          if (found.length >= maxFiles) break;
          await _scanInto(root, found);
        }
        found.sort((a, b) {
          final byFolder = a.folder.compareTo(b.folder);
          if (byFolder != 0) return byFolder;
          final bySub = a.subfolder.toLowerCase().compareTo(b.subfolder.toLowerCase());
          if (bySub != 0) return bySub;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        _videos = List.unmodifiable(found);
        _byId
          ..clear()
          ..addEntries(found.map((v) => MapEntry(v.id, v)));
      } while (_rescanQueued);
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> _scanInto(String root, List<DeviceVideo> found) async {
    final dir = Directory(root);
    if (!await dir.exists()) return;
    final entities = dir
        .list(recursive: true, followLinks: false)
        // Un sous-dossier interdit (corbeille, dossier système) ne doit pas
        // arrêter le reste du parcours.
        .handleError((Object e) => debugPrint('DeviceLibrary: $e'));
    await for (final entity in entities) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root);
      if (p.split(relative).any((part) => part.startsWith('.'))) continue;
      if (!isDeviceVideoPath(entity.path)) continue;
      try {
        final stat = await entity.stat();
        found.add(DeviceVideo(
          path: entity.path,
          folder: root,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
          progress: _progress[entity.path],
        ));
      } on FileSystemException catch (e) {
        debugPrint('DeviceLibrary: ${entity.path} illisible: $e');
      }
      if (found.length >= maxFiles) return;
    }
  }

  /// Ajoute un dossier suivi. Faux quand l'accès est refusé ou que le dossier
  /// n'existe pas — l'écran le dit.
  Future<bool> addFolder(String path) async {
    await initialize();
    final normalized = p.normalize(path);
    if (!await DeviceVideoAccess.ensure()) return false;
    if (!await Directory(normalized).exists()) return false;
    if (_scannedRoots.any((root) => p.equals(root, normalized) || p.isWithin(root, normalized))) {
      return true;
    }
    // Un dossier parent remplace ses enfants déjà suivis : sans cela, chaque
    // vidéo des enfants apparaîtrait deux fois.
    _folders
      ..removeWhere((root) => p.isWithin(normalized, root))
      ..add(normalized);
    await _save();
    _rewatch();
    await rescan();
    return true;
  }

  Future<void> removeFolder(String path) async {
    if (!_folders.remove(path)) return;
    await _save();
    _rewatch();
    await rescan();
  }

  /// iOS : range dans le dossier de l'app les vidéos choisies dans Fichiers.
  /// Le sélecteur les a déjà copiées dans un dossier temporaire ; on les
  /// déplace plutôt que de les recopier, un film pèse plusieurs Go.
  Future<int> importFiles(List<String> paths) async {
    await initialize();
    final target = _appFolder;
    if (target == null) return 0;
    var imported = 0;
    for (final source in paths) {
      if (!isDeviceVideoPath(source)) continue;
      final destination = await _freeName(target, p.basename(source));
      try {
        try {
          await File(source).rename(destination);
        } on FileSystemException {
          // Pas le même volume : la copie est le seul chemin.
          await File(source).copy(destination);
          await File(source).delete();
        }
        imported++;
      } on FileSystemException catch (e) {
        debugPrint('DeviceLibrary: import de $source impossible: $e');
      }
    }
    if (imported > 0) await rescan();
    return imported;
  }

  Future<String> _freeName(String dir, String name) async {
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var candidate = p.join(dir, name);
    var n = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(dir, '$base ($n)$ext');
      n++;
    }
    return candidate;
  }

  /// Supprime le fichier lui-même. Réservé au dossier de l'app : dans un
  /// dossier suivi, le fichier appartient à l'utilisateur, pas à Onyx.
  Future<void> deleteVideo(DeviceVideo video) async {
    final app = _appFolder;
    if (app == null || !p.isWithin(app, video.path)) return;
    try {
      await File(video.path).delete();
    } on FileSystemException catch (e) {
      debugPrint('DeviceLibrary: suppression impossible: $e');
    }
    if (_progress.remove(video.path) != null) await _save();
    await rescan();
  }

  /// Le fichier d'une vidéo de l'appareil, s'il est encore là.
  String? pathFor(int id) {
    if (!isDeviceVideoId(id)) return null;
    final path = _byId[id]?.path;
    if (path == null || !File(path).existsSync()) return null;
    return path;
  }

  DeviceVideoProgress? progressFor(int id) {
    final path = _byId[id]?.path;
    return path == null ? null : _progress[path];
  }

  Future<void> recordProgress({
    required int id,
    required int positionSeconds,
    required int durationSeconds,
    required bool isFinished,
  }) async {
    final video = _byId[id];
    if (video == null) return;
    final next = DeviceVideoProgress(
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      isFinished: isFinished,
      updatedAt: DateTime.now(),
    );
    _progress[video.path] = next;
    final updated = video.withProgress(next);
    _byId[id] = updated;
    _videos = List.unmodifiable([
      for (final v in _videos) v.id == id ? updated : v,
    ]);
    notifyListeners();
    await _save();
  }

  /// Le suivi des dossiers : sur ordinateur, le système prévient d'un fichier
  /// ajouté ou retiré, et la liste se refait d'elle-même. Android et iOS n'ont
  /// pas d'équivalent fiable pour le stockage partagé ; l'écran rescanne à son
  /// ouverture et au retour au premier plan.
  void _rewatch() {
    for (final watch in _watches) {
      unawaited(watch.cancel());
    }
    _watches.clear();
    if (!AppPlatform.isDesktop) return;
    for (final root in _scannedRoots) {
      try {
        _watches.add(Directory(root).watch(recursive: true).listen(
          (event) {
            if (!isDeviceVideoPath(event.path) && event.type != FileSystemEvent.delete) {
              return;
            }
            // Une copie de film émet des centaines d'événements : un seul
            // scan, une fois le calme revenu.
            _watchDebounce?.cancel();
            _watchDebounce = Timer(const Duration(seconds: 2), () => unawaited(rescan()));
          },
          onError: (Object e) => debugPrint('DeviceLibrary: suivi de $root interrompu: $e'),
        ));
      } on FileSystemException catch (e) {
        debugPrint('DeviceLibrary: suivi de $root impossible: $e');
      }
    }
  }

  @override
  void dispose() {
    _watchDebounce?.cancel();
    for (final watch in _watches) {
      unawaited(watch.cancel());
    }
    super.dispose();
  }
}
