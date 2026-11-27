import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/tr.dart';
import '../models/calendar.dart';
import '../models/calendar_feed.dart';
import '../models/media.dart';
import '../services/api_client.dart';
import '../services/client_log.dart';

/// Le calendrier des sorties (« À venir ») du compte connecté.
///
/// Le serveur décide qui y figure et pourquoi (ADR
/// 2026-11-27-tsuky-calendrier-sorties-serveur) : séries regardées, suivies,
/// demandées, et séries que la bibliothèque reçoit. Ce provider relit
/// `GET /api/calendar`, le traduit pour les vues, et porte l'état des vues
/// (mode, semaine, mois, jour choisi) et les demandes d'ouverture de l'onglet.
///
/// « Suivre » et « Ne plus suivre » s'affichent tout de suite, puis la
/// réponse du serveur fait foi : un échec remet l'état d'avant.
///
/// Un serveur sans la capacité `calendar` laisse tout vide ([available]
/// faux) : l'accueil masque sa rangée et l'app se comporte comme avant.
class CalendarProvider extends ChangeNotifier {
  CalendarProvider(this.apiClient, {DateTime? clock})
      : _fixedClock = clock,
        _baseDay = _dateOnly(clock ?? DateTime.now());

  final ApiClient apiClient;

  /// Horloge figée des tests ; sinon le jour courant de l'appareil.
  final DateTime? _fixedClock;

  DateTime _baseDay;

  CalendarViewMode _desktopMode = CalendarViewMode.week;
  CalendarViewMode get desktopMode => _desktopMode;

  late DateTime _selectedDate = _baseDay;
  DateTime get selectedDate => _selectedDate;

  late DateTime _weekStart = _baseDay;
  DateTime get weekStart => _weekStart;

  late DateTime _focusedMonth = DateTime(_baseDay.year, _baseDay.month);
  DateTime get focusedMonth => _focusedMonth;

  /// Compteur incrémenté lorsqu'un écran demande à la coquille d'ouvrir
  /// l'onglet « À venir » (depuis « Tout voir › » ou « Voir dans le calendrier › »).
  int _openTabVersion = 0;
  int get openTabVersion => _openTabVersion;

  List<CalendarEntry> _allEntries = const [];
  Map<String, CalendarFollowedShow> _followedById = {};

  /// Choix en cours d'envoi, par identifiant TMDB : vrai suit, faux retire.
  /// Ils priment sur la dernière réponse du serveur jusqu'à la suivante.
  final Map<int, bool> _pendingChoices = {};

  /// Sorties ajoutées à la volée par « Suivre », le temps que le serveur
  /// rende le programme complet.
  final List<CalendarEntry> _optimisticEntries = [];

  // La fenêtre chargée. Une navigation qui en sort la fait élargir.
  DateTime? _loadedFrom;
  DateTime? _loadedTo;

  int _request = 0;
  bool _disposed = false;
  bool _loaded = false;
  bool _loading = false;
  bool _available = true;
  String? _errorMessage;

  /// Faux quand le serveur ne connaît pas le calendrier.
  bool get available => _available;
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get errorMessage => _errorMessage;

  /// Au plus 400 jours par requête, côté serveur.
  static const _maxSpanDays = 390;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get today => _baseDay;

  DateTime _now() => _fixedClock ?? DateTime.now();

  // ---------------------------------------------------------------------------
  // Chargement

  /// Charge le calendrier une première fois ; les appels suivants ne relisent
  /// que si la dernière lecture date de plus de [maxAge].
  DateTime? _lastLoad;
  Future<void> ensureLoaded({Duration maxAge = const Duration(minutes: 15)}) {
    final last = _lastLoad;
    if (_loading) return Future.value();
    if (last != null && _now().difference(last) < maxAge) {
      return Future.value();
    }
    return load();
  }

  /// Relit le calendrier. Un échec garde ce qu'on avait : une coupure réseau
  /// ne vide pas l'onglet, elle s'y signale.
  Future<void> load() {
    final day = _dateOnly(_now());
    if (day != _baseDay) _rollDay(day);
    final from = _loadedFrom ?? DateTime(day.year, day.month - 1, 1);
    final to = _loadedTo ?? day.add(const Duration(days: 180));
    return _load(from, to);
  }

  Future<void> _load(DateTime from, DateTime to) async {
    final request = ++_request;
    _loading = true;
    notifyListeners();
    try {
      final feed =
          await apiClient.getCalendar(from: from, to: to, today: _baseDay);
      if (_disposed || request != _request) return;
      _loadedFrom = from;
      _loadedTo = to;
      _lastLoad = _now();
      _apply(feed);
      _errorMessage = null;
    } catch (e) {
      if (_disposed || request != _request) return;
      ClientLog.error('CalendarProvider: calendrier indisponible: $e');
      _errorMessage = tr('Impossible de charger le calendrier.');
    } finally {
      if (!_disposed && request == _request) {
        _loading = false;
        _loaded = true;
        notifyListeners();
      }
    }
  }

  /// Élargit la fenêtre chargée pour couvrir [start]–[end] (navigation
  /// semaine ou mois), sans dépasser ce que le serveur accepte.
  void _cover(DateTime start, DateTime end) {
    final from = _loadedFrom;
    final to = _loadedTo;
    if (from == null || to == null) return; // le premier chargement s'en charge
    if (!start.isBefore(from) && !end.isAfter(to)) return;
    var newFrom = start.isBefore(from) ? start : from;
    var newTo = end.isAfter(to) ? end : to;
    if (newTo.difference(newFrom).inDays > _maxSpanDays) {
      // Trop large : on recentre sur ce que l'on regarde.
      newFrom = start.subtract(const Duration(days: 31));
      newTo = newFrom.add(const Duration(days: _maxSpanDays));
    }
    unawaited(_load(newFrom, newTo));
  }

  void _rollDay(DateTime day) {
    final previous = _baseDay;
    _baseDay = day;
    if (_selectedDate == previous) _selectedDate = day;
    if (_weekStart == previous) _weekStart = day;
  }

  void _apply(CalendarFeed? feed) {
    if (feed == null) {
      _available = false;
      _allEntries = const [];
      _followedById = {};
      _optimisticEntries.clear();
      return;
    }
    _available = true;
    _allEntries = [
      for (final e in feed.entries)
        if (_toEntry(e) case final entry?) entry,
    ];
    _followedById = {
      for (final f in feed.followed)
        if (f.tmdbId > 0) _showKey(f.tmdbId): _toFollowed(f),
    };
    // Le serveur a répondu après l'envoi des choix : sa réponse les contient.
    _pendingChoices.clear();
    _optimisticEntries.clear();
  }

  /// Vide tout au changement de serveur ou de compte, puis relit.
  void reset() {
    _request++;
    _allEntries = const [];
    _followedById = {};
    _pendingChoices.clear();
    _optimisticEntries.clear();
    _loadedFrom = null;
    _loadedTo = null;
    _lastLoad = null;
    _loaded = false;
    _loading = false;
    _available = true;
    _errorMessage = null;
    notifyListeners();
    unawaited(load());
  }

  // ---------------------------------------------------------------------------
  // Traduction de la réponse

  static String _showKey(int tmdbId) => 'tv:$tmdbId';

  static CalendarSource _source(String raw) => switch (raw) {
        'watching' => CalendarSource.watching,
        'followed' => CalendarSource.followed,
        'request' => CalendarSource.request,
        _ => CalendarSource.server,
      };

  static double _hue(int tmdbId) => ((tmdbId * 47) % 360).toDouble();

  static String _episodeLabel(int season, int episode) =>
      tr('S{0} · É{1}', [season, episode]);

  static String _subtitle(CalendarFeedEntry e) {
    if (e.kind == 'movie') {
      return switch (e.releaseType) {
        'digital' => tr('Film · sortie numérique'),
        'physical' => tr('Film · sortie en DVD / Blu-ray'),
        'theatrical' => tr('Film · au cinéma'),
        _ => tr('Film'),
      };
    }
    final label = _episodeLabel(e.seasonNumber, e.episodeNumber);
    return switch (e.episodeType) {
      'finale' => '$label · ${tr('Finale')}',
      'premiere' when e.seasonNumber <= 1 => '$label · ${tr('Nouvelle série')}',
      'premiere' => '$label · ${tr('Reprise')}',
      _ => label,
    };
  }

  static CalendarEntry? _toEntry(CalendarFeedEntry e) {
    final date = DateTime.tryParse(e.airDate);
    if (date == null || e.tmdbId <= 0) return null;
    final movie = e.kind == 'movie';
    return CalendarEntry(
      id: e.id,
      showId: movie ? 'movie:${e.tmdbId}' : _showKey(e.tmdbId),
      title: e.title,
      kind: movie ? CalendarEntryKind.movie : CalendarEntryKind.show,
      date: _dateOnly(date),
      subtitle: _subtitle(e),
      source: _source(e.source),
      hue: _hue(e.tmdbId),
      posterUrl: e.posterUrl.isEmpty ? null : e.posterUrl,
      ready: e.ready,
      mediaId: e.mediaId > 0 ? e.mediaId : null,
      tmdbId: e.tmdbId,
      episodeMediaId: e.episodeMediaId > 0 ? e.episodeMediaId : null,
      seasonNumber: movie ? null : e.seasonNumber,
      episodeNumber: movie ? null : e.episodeNumber,
    );
  }

  static CalendarFollowedShow _toFollowed(CalendarFeedShow f) =>
      CalendarFollowedShow(
        id: _showKey(f.tmdbId),
        title: f.title,
        source: _source(f.source),
        hue: _hue(f.tmdbId),
        nextSummary: f.nextSeason > 0
            ? _episodeLabel(f.nextSeason, f.nextEpisode)
            : null,
        mediaId: f.mediaId > 0 ? f.mediaId : null,
        tmdbId: f.tmdbId,
      );

  // ---------------------------------------------------------------------------
  // Lecture pour les vues

  bool _hiddenByPendingChoice(CalendarEntry entry) =>
      entry.kind == CalendarEntryKind.show &&
      entry.tmdbId != null &&
      _pendingChoices[entry.tmdbId] == false;

  /// Sorties visibles, triées par date.
  List<CalendarEntry> get entries {
    final visible = [
      for (final entry in _allEntries)
        if (!_hiddenByPendingChoice(entry)) entry,
      for (final entry in _optimisticEntries)
        if (!_allEntries.any((e) => e.id == entry.id)) entry,
    ];
    if (_optimisticEntries.isNotEmpty) {
      visible.sort((a, b) => a.date.compareTo(b.date));
    }
    return visible;
  }

  /// Sorties prévues dans les 7 prochains jours (pour la rangée d'accueil).
  List<CalendarEntry> get thisWeekEntries => entries.where((e) {
        final delta = e.date.difference(_baseDay).inDays;
        return delta >= 0 && delta < 7;
      }).toList();

  /// Vrai lorsqu'au moins une sortie du jour est marquée disponible.
  bool get hasAvailableToday => entries.any(
        (e) => e.ready && e.date.difference(_baseDay).inDays == 0,
      );

  /// Liste des séries actuellement suivies dans le calendrier.
  List<CalendarFollowedShow> get followedShows => [
        for (final show in _followedById.values)
          if (show.tmdbId == null || _pendingChoices[show.tmdbId] != false)
            show,
      ];

  /// Clé stable d'une série de la bibliothèque, celle des séries suivies
  /// quand TMDB la connaît.
  static String keyForShow(Media show) {
    final tmdbId = show.tmdbId;
    return tmdbId != null && tmdbId > 0 ? _showKey(tmdbId) : 'media:${show.id}';
  }

  CalendarFollowedShow? _findShow(Media show) {
    final tmdbId = show.tmdbId;
    if (tmdbId != null && _pendingChoices[tmdbId] == false) return null;
    final byKey = _followedById[keyForShow(show)];
    if (byKey != null) return byKey;
    for (final item in _followedById.values) {
      if (item.mediaId == show.id) return item;
    }
    return null;
  }

  bool isFollowingShow(Media show) {
    final tmdbId = show.tmdbId;
    if (tmdbId != null && _pendingChoices[tmdbId] == true) return true;
    return _findShow(show) != null;
  }

  /// Texte discret expliquant un suivi automatique, ou `null` si suivi à la main.
  String? followReasonFor(Media show) {
    final found = _findShow(show);
    if (found == null) return null;
    return switch (found.source) {
      CalendarSource.watching => tr('Suivie car vous la regardez'),
      CalendarSource.request => tr('Suivie car vous l’avez demandée'),
      CalendarSource.server || CalendarSource.followed => null,
    };
  }

  List<CalendarEntry> entriesOn(DateTime day) {
    final target = _dateOnly(day);
    return entries.where((e) => e.date == target).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Suivre / ne plus suivre

  /// Bascule le suivi d'une série. Rend le nouvel état tout de suite ; le
  /// serveur confirme ensuite, et un refus remet l'état d'avant.
  ///
  /// [nextAirDate] et [nextCaption], quand la fiche les connaît, font
  /// apparaître le prochain épisode avant même la réponse du serveur.
  bool toggleFollowShow(Media show,
      {String? nextAirDate, String? nextCaption}) {
    final tmdbId = show.tmdbId;
    if (tmdbId == null || tmdbId <= 0) {
      // Sans identifiant TMDB, le serveur ne saurait pas quoi suivre.
      _errorMessage =
          tr('Cette série n’est pas identifiée : impossible de la suivre.');
      notifyListeners();
      return false;
    }
    final follow = !isFollowingShow(show);
    _pendingChoices[tmdbId] = follow;
    if (follow) _addOptimisticEntry(show, tmdbId, nextAirDate, nextCaption);
    if (!follow) {
      _optimisticEntries.removeWhere((e) => e.tmdbId == tmdbId);
    }
    notifyListeners();
    unawaited(_sendChoice(tmdbId, follow));
    return follow;
  }

  void _addOptimisticEntry(
      Media show, int tmdbId, String? nextAirDate, String? nextCaption) {
    final parsed = nextAirDate == null ? null : DateTime.tryParse(nextAirDate);
    if (parsed == null) return;
    final key = _showKey(tmdbId);
    if (_allEntries.any((e) => e.showId == key)) return;
    _optimisticEntries.add(CalendarEntry(
      id: 'pending:$key',
      showId: key,
      title: show.title,
      kind: CalendarEntryKind.show,
      date: _dateOnly(parsed),
      subtitle: nextCaption ?? tr('Nouvel épisode'),
      source: CalendarSource.followed,
      hue: _hue(tmdbId),
      posterUrl: show.posterUrl,
      mediaId: show.id,
      tmdbId: tmdbId,
    ));
  }

  Future<void> _sendChoice(int tmdbId, bool follow) async {
    try {
      if (follow) {
        await apiClient.followCalendarShow(tmdbId);
      } else {
        await apiClient.unfollowCalendarShow(tmdbId);
      }
    } catch (e) {
      if (_disposed) return;
      ClientLog.error('CalendarProvider: suivi $tmdbId ($follow) refusé: $e');
      _pendingChoices.remove(tmdbId);
      _optimisticEntries.removeWhere((entry) => entry.tmdbId == tmdbId);
      _errorMessage = follow
          ? tr('Impossible de suivre cette série pour le moment.')
          : tr('Impossible de retirer cette série pour le moment.');
      notifyListeners();
      return;
    }
    if (_disposed) return;
    // Le programme d'une série tout juste suivie vient du serveur.
    await load();
  }

  /// Retire une série depuis le panneau « Gérer les séries suivies ».
  void unfollowById(String id) {
    final show = _followedById[id];
    final tmdbId = show?.tmdbId;
    if (show == null || tmdbId == null) return;
    _pendingChoices[tmdbId] = false;
    _optimisticEntries.removeWhere((e) => e.tmdbId == tmdbId);
    notifyListeners();
    unawaited(_sendChoice(tmdbId, false));
  }

  // ---------------------------------------------------------------------------
  // État des vues

  void setDesktopMode(CalendarViewMode mode) {
    if (_desktopMode == mode) return;
    _desktopMode = mode;
    notifyListeners();
  }

  void shiftWeek(int deltaWeeks) {
    _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
    _cover(_weekStart, _weekStart.add(const Duration(days: 6)));
    notifyListeners();
  }

  void shiftMonth(int deltaMonths) {
    _focusedMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + deltaMonths);
    _coverMonth(_focusedMonth);
    notifyListeners();
  }

  void _coverMonth(DateTime month) {
    // La grille d'un mois montre aussi la fin du précédent et le début du
    // suivant.
    _cover(month.subtract(const Duration(days: 7)),
        DateTime(month.year, month.month + 1, 7));
  }

  void selectDate(DateTime date) {
    final normalized = _dateOnly(date);
    _selectedDate = normalized;
    _focusedMonth = DateTime(normalized.year, normalized.month);
    _coverMonth(_focusedMonth);
    notifyListeners();
  }

  /// Demande à la coquille d'ouvrir l'onglet « À venir », optionnellement
  /// positionné sur [date] (depuis le compte à rebours d'une fiche).
  void openCalendar({DateTime? date}) {
    if (date != null) {
      final normalized = _dateOnly(date);
      _selectedDate = normalized;
      _focusedMonth = DateTime(normalized.year, normalized.month);
      _weekStart = normalized;
      _coverMonth(_focusedMonth);
    }
    _openTabVersion++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
