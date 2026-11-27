import 'package:material_ui/material_ui.dart';

import '../../l10n/tr.dart';
import '../../models/calendar.dart';
import '../../models/media.dart';
import '../../models/media_request.dart';
import '../../navigation/detail_flight.dart';
import '../../widgets/global/onyx_toast.dart';
import '../requests/request_detail_launch.dart';

/// Ouvre la fiche d'une sortie du calendrier.
///
/// Un titre de la bibliothèque ouvre sa fiche du serveur, d'où l'épisode
/// déjà là se lance ; un titre demandé que le serveur n'a pas encore ouvre
/// sa fiche de demande, qui dit où il en est. Sans l'un ni l'autre, un
/// toast rappelle la sortie.
Future<void> openCalendarEntry(BuildContext context, CalendarEntry entry) {
  final movie = entry.kind == CalendarEntryKind.movie;
  final mediaId = entry.mediaId;
  if (mediaId != null) {
    return openMediaDetail(
      context,
      Media(
        id: mediaId,
        type: movie ? MediaType.movie : MediaType.show,
        title: entry.title,
        duration: 0,
        posterUrl: entry.posterUrl,
        tmdbId: entry.tmdbId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      measureCard: false,
    );
  }
  final tmdbId = entry.tmdbId;
  if (tmdbId != null) {
    return openRequestDetail(
      context,
      RequestMediaItem(
        id: tmdbId,
        mediaType: movie ? RequestMediaType.movie : RequestMediaType.tv,
        title: entry.title,
        overview: '',
        posterPath: tmdbImagePath(entry.posterUrl),
        backdropPath: null,
        releaseDate: null,
        rating: 0,
        status: RequestMediaStatus.pending,
      ),
      measureCard: false,
    );
  }
  showOnyxToast(context, tr('{0} · {1}', [entry.title, entry.subtitle]));
  return Future.value();
}

/// Le chemin TMDB d'une URL d'image TMDB (« …/t/p/w342/abc.jpg » →
/// « /abc.jpg »), que la fiche de demande remet à sa taille. Null pour une
/// image qui ne vient pas de TMDB.
@visibleForTesting
String? tmdbImagePath(String? url) {
  if (url == null) return null;
  final match =
      RegExp(r'^https://image\.tmdb\.org/t/p/[^/]+(/.+)$').firstMatch(url);
  return match?.group(1);
}
