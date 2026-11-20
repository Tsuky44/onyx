import 'media_library.dart';

/// Une miette du fil d'Ariane de l'explorateur de dossiers.
class FsCrumb {
  const FsCrumb({required this.name, required this.path});

  final String name;
  final String path;

  factory FsCrumb.fromJson(Map<String, dynamic> json) => FsCrumb(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
      );
}

/// Un sous-dossier que le serveur montre dans l'explorateur, avec ce qu'il en
/// a deviné : son contenu (films, séries, autre), s'il sert déjà à une
/// bibliothèque et combien de vidéos il porte (ADR-0165).
class FsFolder {
  const FsFolder({
    required this.name,
    required this.path,
    required this.kind,
    required this.covered,
    required this.videoCount,
    required this.videoCountCapped,
  });

  final String name;
  final String path;
  final LibraryKind kind;

  /// Vrai quand une bibliothèque couvre déjà ce dossier (ou l'un de ses
  /// parents) : il se parcourt, il ne se choisit pas.
  final bool covered;
  final int videoCount;

  /// Le serveur arrête de compter à un plafond : « 50+ vidéos », pas « 50 ».
  final bool videoCountCapped;

  factory FsFolder.fromJson(Map<String, dynamic> json) => FsFolder(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        kind: LibraryKind.parse(json['kind'] as String?),
        covered: json['covered'] == true,
        videoCount: (json['video_count'] as num?)?.toInt() ?? 0,
        videoCountCapped: json['video_count_capped'] == true,
      );
}

/// Ce que `GET /api/fs/browse` rend pour un dossier du serveur.
class FsListing {
  const FsListing({
    required this.root,
    required this.path,
    required this.parent,
    required this.breadcrumb,
    required this.folders,
    required this.readable,
    required this.emptyRoot,
  });

  /// Le point de montage que le serveur expose (`/media`). On n'en sort pas.
  final String root;

  /// Le dossier affiché.
  final String path;

  /// Le dossier du dessus ; null à la racine.
  final String? parent;
  final List<FsCrumb> breadcrumb;
  final List<FsFolder> folders;

  /// Faux quand le serveur n'a pas le droit de lire ce dossier.
  final bool readable;

  /// Vrai quand la racine elle-même est vide : rien n'a été monté dans le
  /// conteneur, ce qui est un problème de compose et pas de bibliothèque.
  final bool emptyRoot;

  factory FsListing.fromJson(Map<String, dynamic> json) => FsListing(
        root: json['root'] as String? ?? '',
        path: json['path'] as String? ?? '',
        parent: json['parent'] as String?,
        breadcrumb: [
          for (final crumb in json['breadcrumb'] as List<dynamic>? ?? const [])
            FsCrumb.fromJson(crumb as Map<String, dynamic>),
        ],
        folders: [
          for (final folder in json['folders'] as List<dynamic>? ?? const [])
            FsFolder.fromJson(folder as Map<String, dynamic>),
        ],
        readable: json['readable'] != false,
        emptyRoot: json['empty_root'] == true,
      );
}

/// Pourquoi un test de la clé TMDB a réussi ou non.
enum TmdbTestReason {
  ok('ok'),

  /// TMDB a répondu et refuse la clé (la clé API v3 est attendue, pas le
  /// jeton d'accès).
  invalidKey('invalid_key'),

  /// Le serveur n'a pas pu joindre TMDB : réseau, DNS, pare-feu. La clé n'est
  /// pas en cause.
  unreachable('unreachable'),

  /// Ni clé saisie ni clé enregistrée.
  noKey('no_key'),

  /// Une cause que cette version de l'app ne connaît pas.
  unknown('');

  const TmdbTestReason(this.wire);

  final String wire;

  static TmdbTestReason parse(String? wire) => TmdbTestReason.values
      .firstWhere((r) => r.wire == wire && wire != '', orElse: () => unknown);
}

/// La réponse de `POST /api/settings/tmdb/test`.
class TmdbTest {
  const TmdbTest({required this.ok, required this.reason, this.message = ''});

  final bool ok;
  final TmdbTestReason reason;

  /// La phrase du serveur ; l'app s'en sert quand elle ne connaît pas la cause.
  final String message;

  factory TmdbTest.fromJson(Map<String, dynamic> json) => TmdbTest(
        ok: json['ok'] == true,
        reason: TmdbTestReason.parse(json['reason'] as String?),
        message: json['message'] as String? ?? '',
      );
}

/// Où en est la première installation, selon `GET /api/setup/state`.
class SetupState {
  const SetupState({
    required this.completed,
    required this.libraryCount,
    required this.librariesDone,
    required this.tmdbDone,
    required this.requestsDone,
    required this.requestsAvailable,
  });

  /// Vrai une fois l'assistant terminé ou ignoré : il ne se rouvre plus.
  final bool completed;
  final int libraryCount;
  final bool librariesDone;
  final bool tmdbDone;
  final bool requestsDone;

  /// Faux tant que TMDB n'est pas réglé : le serveur refuse (409) un service
  /// de demandes sans clé TMDB.
  final bool requestsAvailable;

  /// Les étapes qui comptent pour la checklist : bibliothèques et TMDB
  /// toujours, les demandes quand elles sont déjà possibles ou faites.
  int get totalSteps => 3;
  int get doneSteps => [librariesDone, tmdbDone, requestsDone].where((d) => d).length;

  bool get allDone => librariesDone && tmdbDone && requestsDone;

  factory SetupState.fromJson(Map<String, dynamic> json) {
    final libraries = json['libraries'] as Map<String, dynamic>? ?? const {};
    final tmdb = json['tmdb'] as Map<String, dynamic>? ?? const {};
    final requests = json['requests'] as Map<String, dynamic>? ?? const {};
    return SetupState(
      completed: json['completed'] == true,
      libraryCount: (libraries['count'] as num?)?.toInt() ?? 0,
      librariesDone: libraries['done'] == true,
      tmdbDone: tmdb['done'] == true,
      requestsDone: requests['done'] == true,
      requestsAvailable: requests['available'] == true,
    );
  }

  SetupState copyWith({
    bool? completed,
    int? libraryCount,
    bool? librariesDone,
    bool? tmdbDone,
    bool? requestsDone,
    bool? requestsAvailable,
  }) =>
      SetupState(
        completed: completed ?? this.completed,
        libraryCount: libraryCount ?? this.libraryCount,
        librariesDone: librariesDone ?? this.librariesDone,
        tmdbDone: tmdbDone ?? this.tmdbDone,
        requestsDone: requestsDone ?? this.requestsDone,
        requestsAvailable: requestsAvailable ?? this.requestsAvailable,
      );
}
