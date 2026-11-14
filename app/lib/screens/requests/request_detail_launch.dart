import 'package:flutter/material.dart';

import '../../models/media_request.dart';
import '../../navigation/detail_flight.dart';
import '../../utils/poster_url.dart';
import 'request_detail_screen.dart';

/// Ouvre la fiche d'une demande depuis sa carte, par l'envol commun à toutes
/// les fiches ([pushDetailFlight]).
///
/// [measureCard] faux quand [cardContext] n'est pas une carte (la recherche du
/// système de l'Apple TV, dont les affiches ne sont pas des widgets) : la
/// fiche s'ouvre alors par une route ordinaire.
Future<void> openRequestDetail(
  BuildContext cardContext,
  RequestMediaItem item, {
  bool measureCard = true,
}) {
  return pushDetailFlight(
    cardContext,
    posterUrl: cardPosterUrl(item.posterUrl),
    backdropUrl: detailBackdropUrl(item.backdropUrl),
    measureCard: measureCard,
    builder: (_) => RequestDetailScreen(item: item),
  );
}
