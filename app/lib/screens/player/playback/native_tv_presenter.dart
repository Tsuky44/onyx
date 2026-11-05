import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../../../services/client_log.dart';
import 'aether_video_fit.dart';
import 'native_tv_fallback.dart';
import 'native_tv_intent.dart';
import 'native_tv_preference.dart';
import 'native_tv_screen.dart';

export 'native_tv_fallback.dart';
export 'native_tv_intent.dart';
export 'native_tv_panels.dart';
export 'native_tv_questions.dart';
export 'native_tv_spec.dart';

/// Si le lecteur prend l'écran natif d'Apple TV (`AVPlayerViewController`)
/// au lieu de son interface Flutter.
///
/// Le seul endroit où cela se décide pour l'appareil : Apple TV et le réglage
/// Natif / Onyx de l'utilisateur (`native_tv_preference.dart`). Ce qui dépend
/// du média, lui, passe par `nativeTvFallbackFor` (`native_tv_fallback.dart`).
bool isNativeTvPlayerEligible() => NativeTvPlayerPreference.eligibleHere;

/// Ce que l'écran natif retient d'une spec à l'autre et que l'interface Onyx
/// garde dans ses propres widgets : l'état du bouton « Démarrer une séance »,
/// le moment où l'épisode suivant a été proposé.
class NativeTvMemory {
  /// Le panneau des épisodes a demandé sa saison : une seule fois par
  /// lecteur, même quand le chargement échoue.
  bool episodesRequested = false;

  bool watchPartyStarting = false;
  String? watchPartyError;

  int? _nextUpEpisodeId;
  Duration? _nextUpTransition;
  int? _nextUpDeferredId;

  /// Le moment de la proposition de [episodeId], retenu à sa première
  /// demande : la spec ne doit pas changer à chaque position.
  Duration nextUpTransition(int episodeId, Duration Function() now) {
    if (_nextUpEpisodeId != episodeId || _nextUpTransition == null) {
      _nextUpEpisodeId = episodeId;
      _nextUpTransition = now();
    }
    return _nextUpTransition!;
  }

  /// « Plus tard » : la proposition de [episodeId] ne revient pas.
  void deferNextUp(int episodeId) => _nextUpDeferredId = episodeId;
  bool nextUpDeferred(int episodeId) => _nextUpDeferredId == episodeId;
}

/// Tient l'écran natif d'Apple TV pour un lecteur : le présente, le garde à
/// jour, le ferme, et rend ses événements en [NativeTvIntent].
///
/// Dart reste maître de l'état : le natif ne coche rien de lui-même, il attend
/// la spec suivante. [sync] est donc appelé à chaque changement d'état de
/// l'écran, et ne passe le pont que quand la spec a vraiment changé.
class NativeTvPresenter {
  NativeTvPresenter({
    required NativeTvScreen screen,
    required void Function(NativeTvIntent intent) onIntent,
  })  : _screen = screen,
        _onIntent = onIntent {
    // Construit avec l'écran du lecteur, donc avant la première ouverture :
    // les pistes texte n'entrent dans le menu d'AVKit que déclarées au
    // chargement (spike Apple TV, Q5).
    _run('préparation des sous-titres',
        () => screen.prepareSubtitles(nativeTvLoadSubtitles()));
    _events = screen.events.listen(
      _onEvent,
      onError: (Object error) {
        ClientLog.error(
            'Lecteur natif : flux d’événements interrompu ($error)');
      },
    );
  }

  final NativeTvScreen _screen;
  final void Function(NativeTvIntent intent) _onIntent;
  late final StreamSubscription<OnyxAppleNativeEvent> _events;

  bool _shown = false;
  OnyxAppleNativeSpec? _sent;
  OnyxAppleVideoFit? _sentFit;
  bool _disposed = false;

  /// Vit et meurt avec ce lecteur, comme l'écran natif.
  final NativeTvMemory memory = NativeTvMemory();

  /// Le natif a refusé (`unavailable`) ou l'utilisateur l'a fermé : il ne se
  /// présente plus pour ce lecteur. Le représenter après un refus, c'était
  /// un aller-retour noir à chaque changement d'état.
  bool _retired = false;

  /// La raison du dernier `unavailable` : un refus vaut pour toute la vie de
  /// ce lecteur, et la règle de repli la reprend (`bitmapSubtitles` ne vaut
  /// que pour les pistes image).
  OnyxAppleNativeReason? _refusal;
  OnyxAppleNativeReason? get refusal => _refusal;

  /// L'écran natif est demandé et n'a pas été refusé ni fermé.
  ///
  /// Vrai dès la demande, sans attendre le natif : l'interface Flutter se
  /// retire au même moment, et un refus la rend.
  bool get isShown => _shown;

  /// Rapproche l'écran natif de ce que le lecteur veut : [wanted] le présente
  /// ou le ferme, et [spec] le met à jour quand elle a changé.
  ///
  /// Une fermeture demandée ici n'est pas un retrait : l'interface Flutter a
  /// pu reprendre la main le temps d'une question, le natif revient ensuite.
  void sync({required bool wanted, required OnyxAppleNativeSpec spec}) {
    if (_disposed || _retired) return;
    if (!wanted) {
      if (_shown) _close();
      return;
    }
    if (!_shown) {
      _shown = true;
      _sent = spec;
      _run('présentation', () => _screen.present(spec), failOpen: true);
      return;
    }
    if (spec == _sent) return;
    _sent = spec;
    _run('mise à jour', () => _screen.update(spec));
  }

  /// Le cadrage du mode d'affichage, que la scène Flutter portait elle-même
  /// et qui n'est plus montée. Porté seulement quand il change.
  void syncFit(BoxFit fit, double aspectRatio, Size screen) {
    final resolved = AetherVideoFit.resolve(fit, aspectRatio, screen);
    if (_disposed || !_shown || resolved == _sentFit) return;
    _sentFit = resolved;
    _run('cadrage', () => _screen.setFit(resolved));
  }

  void _close() {
    _forget();
    _run('fermeture', _screen.dismiss);
  }

  /// L'écran n'est plus là : la prochaine spec devra le présenter, pas le
  /// mettre à jour, et la scène Flutter reprend le cadrage.
  void _forget() {
    _shown = false;
    _sent = null;
    _sentFit = null;
  }

  void _onEvent(OnyxAppleNativeEvent event) {
    if (_disposed) return;
    final intent = nativeTvIntentOf(event);
    if (intent == null) {
      debugPrint('Lecteur natif : événement ignoré '
          '(${event.kind.name} ${event.menuId ?? event.actionId ?? ''})');
      return;
    }
    // La fermeture demandée par l'app est déjà connue d'elle.
    if (intent is NativeTvClosed && !intent.byUser) return;
    if (intent is NativeTvClosed || intent is NativeTvUnavailable) {
      _forget();
      // Une piste image que le natif n'a pas su peindre ne le condamne pas :
      // la règle de repli garde Flutter tant qu'elle est choisie, puis le
      // natif revient avec une piste texte.
      _retired = !(intent is NativeTvUnavailable &&
          intent.reason == OnyxAppleNativeReason.bitmapSubtitles);
    }
    if (intent is NativeTvUnavailable) _refusal = intent.reason;
    _onIntent(intent);
  }

  /// [failOpen] : une présentation qui échoue côté Dart (canal absent) vaut un
  /// refus, sinon l'écran resterait noir sans interface.
  void _run(String what, Future<void> Function() call,
      {bool failOpen = false}) {
    unawaited(call().catchError((Object error) {
      ClientLog.error('Lecteur natif : $what refusée ($error)');
      if (failOpen && !_disposed && _shown) {
        _forget();
        _retired = true;
        _refusal = OnyxAppleNativeReason.presentationFailed;
        _onIntent(const NativeTvUnavailable(
          OnyxAppleNativeReason.presentationFailed,
        ));
      }
    }));
  }

  /// Ferme l'écran natif s'il est là, et cesse d'écouter.
  void dispose() {
    if (_disposed) return;
    if (_shown) _close();
    _disposed = true;
    unawaited(_events.cancel());
  }
}
