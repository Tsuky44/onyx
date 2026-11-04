import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../services/client_log.dart';
import '../../../utils/app_platform.dart';
import '../player_menu_choices.dart';
import '../video_display_mode.dart';
import '../widgets/direct_source_label.dart';
import '../widgets/track_label.dart';
import 'aether_video_fit.dart';
import 'native_tv_fallback.dart';
import 'native_tv_screen.dart';
import 'playback_session.dart';
import 'skip_segments.dart';

export 'native_tv_fallback.dart';

/// Si le lecteur prend l'écran natif d'Apple TV (`AVPlayerViewController`)
/// au lieu de son interface Flutter.
///
/// Le seul endroit où cela se décide pour l'appareil : le réglage Natif /
/// Onyx de l'utilisateur viendra s'ajouter ici. Ce qui dépend du média, lui,
/// passe par `nativeTvFallbackFor` (`native_tv_fallback.dart`).
bool isNativeTvPlayerEligible() => AppPlatform.isTvOS;

/// La spec que reçoit l'écran natif, sous un nom du lecteur.
typedef NativeTvSpec = OnyxAppleNativeSpec;

/// Ce que le lecteur sait à cet instant, de quoi bâtir l'écran natif.
///
/// Des valeurs plutôt que le contrôleur : la construction de la spec se teste
/// sans moteur ni écran.
class NativeTvState {
  const NativeTvState({
    required this.title,
    this.subtitle,
    this.posterUrl,
    this.overview,
    required this.rate,
    required this.rates,
    required this.mode,
    this.quality,
    this.serverAudio,
    this.selectedAudioIndex = -1,
    this.engineAudio = const [],
    this.currentEngineAudio,
    this.skipSegment,
    this.hasNextEpisode = false,
  });

  final String title;
  final String? subtitle;
  final String? posterUrl;
  final String? overview;
  final double rate;
  final List<double> rates;
  final VideoDisplayMode mode;

  /// Null quand la qualité n'a pas de menu (lecteur pas encore initialisé).
  final NativeTvQuality? quality;

  /// La liste canonique du serveur, ou null : on retombe alors sur les pistes
  /// que le moteur a énumérées, comme le menu Onyx.
  final List<MediaAudioTrack>? serverAudio;
  final int selectedAudioIndex;
  final List<PlaybackTrack> engineAudio;
  final PlaybackTrack? currentEngineAudio;

  /// Le segment que « Passer » propose maintenant, ou null.
  final SkipSegment? skipSegment;

  /// « Épisode suivant » est proposé.
  final bool hasNextEpisode;
}

/// L'état du menu Qualité.
class NativeTvQuality {
  const NativeTvQuality({
    required this.tiers,
    required this.current,
    required this.isAuto,
    required this.autoAvailable,
    required this.isLocalPlayback,
  });

  final List<QualityTier> tiers;

  /// La clé du barreau joué, ou null en Direct Play.
  final String? current;
  final bool isAuto;
  final bool autoAvailable;
  final bool isLocalPlayback;
}

/// Les identifiants que Dart donne aux menus et aux actions, rendus tels quels
/// par le natif dans ses événements.
abstract final class NativeTvIds {
  const NativeTvIds._();

  static const speed = 'speed';
  static const fit = 'fit';
  static const quality = 'quality';
  static const audio = 'audio';

  static const skipSegment = 'skipSegment';
  static const nextEpisode = 'nextEpisode';

  static const qualityAuto = 'auto';
  static const qualityDirect = 'direct';
  static const qualityTierPrefix = 'tier:';

  /// Une piste de la liste du serveur, par son rang.
  static const audioIndexPrefix = 'index:';

  /// Une piste du moteur, par son identifiant.
  static const audioTrackPrefix = 'track:';
}

/// Construit la spec de l'écran natif. Tous les textes sont traduits ici :
/// Swift n'affiche que ce qu'il reçoit.
abstract final class NativeTvSpecBuilder {
  const NativeTvSpecBuilder._();

  static OnyxAppleNativeSpec build(NativeTvState state) {
    return OnyxAppleNativeSpec(
      title: state.title,
      subtitle: state.subtitle,
      posterUrl: state.posterUrl,
      overview: state.overview,
      menus: [
        _speedMenu(state),
        _fitMenu(state),
        if (state.quality != null) _qualityMenu(state.quality!),
        if (_audioMenu(state) case final audio?) audio,
      ],
      actions: [
        if (state.skipSegment case final segment?)
          OnyxAppleNativeAction(
            id: NativeTvIds.skipSegment,
            label: switch (segment) {
              SkipSegment.recap => tr('Passer le récap'),
              SkipSegment.intro => tr('Passer l’intro'),
            },
          ),
        if (state.hasNextEpisode)
          OnyxAppleNativeAction(
            id: NativeTvIds.nextEpisode,
            label: tr('Épisode suivant'),
          ),
      ],
    );
  }

  static OnyxAppleNativeMenu _speedMenu(NativeTvState state) =>
      OnyxAppleNativeMenu(
        id: NativeTvIds.speed,
        label: tr('Vitesse de lecture'),
        options: [
          for (final rate in state.rates)
            OnyxAppleNativeOption(
              id: '$rate',
              label: PlayerMenuChoices.rateLabel(rate),
              selected: rate == state.rate,
            ),
        ],
      );

  static OnyxAppleNativeMenu _fitMenu(NativeTvState state) =>
      OnyxAppleNativeMenu(
        id: NativeTvIds.fit,
        label: tr('Format d’image'),
        options: [
          for (final mode in VideoDisplayMode.values)
            OnyxAppleNativeOption(
              id: mode.name,
              label: mode.label,
              selected: mode == state.mode,
            ),
        ],
      );

  /// Les mêmes lignes que le menu Onyx : Auto quand le serveur annonce ses
  /// débits, le fichier tel quel, puis l'échelle.
  static OnyxAppleNativeMenu _qualityMenu(NativeTvQuality quality) {
    final auto = quality.isAuto;
    return OnyxAppleNativeMenu(
      id: NativeTvIds.quality,
      label: tr('Qualité'),
      options: [
        if (quality.autoAvailable)
          OnyxAppleNativeOption(
            id: NativeTvIds.qualityAuto,
            label: tr('Auto'),
            selected: auto,
          ),
        OnyxAppleNativeOption(
          id: NativeTvIds.qualityDirect,
          label: directSourceLabel(local: quality.isLocalPlayback).label,
          selected: !auto && quality.current == null,
        ),
        for (final tier in quality.tiers)
          OnyxAppleNativeOption(
            id: '${NativeTvIds.qualityTierPrefix}${tier.key}',
            label: tier.label,
            selected: !auto && quality.current == tier.key,
          ),
      ],
    );
  }

  /// Null quand il n'y a aucune piste à proposer.
  static OnyxAppleNativeMenu? _audioMenu(NativeTvState state) {
    final server = state.serverAudio;
    final List<OnyxAppleNativeOption> options;
    if (server != null && server.isNotEmpty) {
      options = [
        for (var i = 0; i < server.length; i++)
          OnyxAppleNativeOption(
            id: '${NativeTvIds.audioIndexPrefix}$i',
            label: splitTrackLabel(server[i].displayName).$1,
            selected: i == state.selectedAudioIndex,
          ),
      ];
    } else {
      final engine = state.engineAudio;
      options = [
        for (var i = 0; i < engine.length; i++)
          OnyxAppleNativeOption(
            id: '${NativeTvIds.audioTrackPrefix}${engine[i].id}',
            label: engine[i].id == 'no'
                ? tr('Désactivé')
                : engine[i].title ??
                    (engine[i].language != null
                        ? tr('Audio ({0})', [engine[i].language])
                        : tr('Audio {0}', [i + 1])),
            selected: engine[i] == state.currentEngineAudio,
          ),
      ];
    }
    if (options.isEmpty) return null;
    return OnyxAppleNativeMenu(
      id: NativeTvIds.audio,
      label: tr('Audio'),
      options: options,
    );
  }
}

/// Ce qu'un événement natif demande au lecteur. Chaque cas a déjà son
/// gestionnaire dans l'écran du lecteur : ce type ne fait que traduire.
sealed class NativeTvIntent {
  const NativeTvIntent();
}

final class NativeTvSkipSegment extends NativeTvIntent {
  const NativeTvSkipSegment();
}

final class NativeTvNextEpisode extends NativeTvIntent {
  const NativeTvNextEpisode();
}

final class NativeTvSetRate extends NativeTvIntent {
  const NativeTvSetRate(this.rate);
  final double rate;
}

final class NativeTvSetFit extends NativeTvIntent {
  const NativeTvSetFit(this.mode);
  final VideoDisplayMode mode;
}

/// [auto] pour « Auto », sinon [key] : un barreau, ou null pour le Direct.
final class NativeTvSetQuality extends NativeTvIntent {
  const NativeTvSetQuality({this.key, this.auto = false});
  final String? key;
  final bool auto;
}

/// Une piste de la liste du serveur ([serverIndex]) ou du moteur
/// ([engineTrackId]), selon la liste que le menu a proposée.
final class NativeTvSetAudio extends NativeTvIntent {
  const NativeTvSetAudio({this.serverIndex, this.engineTrackId});
  final int? serverIndex;
  final String? engineTrackId;
}

/// Un sous-titre choisi dans le menu AVKit, dans la numérotation du lecteur
/// (`PlaybackTrack.id`) : nul pour « aucun ».
final class NativeTvSetSubtitle extends NativeTvIntent {
  const NativeTvSetSubtitle(this.trackId);
  final String? trackId;
}

/// L'écran natif s'est fermé. [byUser] pour Menu sur la télécommande ; sinon
/// c'est l'app qui l'a demandé.
final class NativeTvClosed extends NativeTvIntent {
  const NativeTvClosed({required this.byUser});
  final bool byUser;
}

/// Le natif ne peut pas jouer ceci : l'écran Flutter reprend la main.
final class NativeTvUnavailable extends NativeTvIntent {
  const NativeTvUnavailable(this.reason);
  final OnyxAppleNativeReason? reason;
}

/// Traduit un événement natif, ou null pour un identifiant inconnu (un natif
/// plus récent que ce Dart) : il est ignoré plutôt que mal compris.
NativeTvIntent? nativeTvIntentOf(OnyxAppleNativeEvent event) {
  switch (event.kind) {
    case OnyxAppleNativeEventKind.action:
      return switch (event.actionId) {
        NativeTvIds.skipSegment => const NativeTvSkipSegment(),
        NativeTvIds.nextEpisode => const NativeTvNextEpisode(),
        _ => null,
      };
    case OnyxAppleNativeEventKind.menuSelected:
      return _menuIntent(event.menuId, event.optionId);
    case OnyxAppleNativeEventKind.subtitleSelected:
      return NativeTvSetSubtitle(event.trackId);
    case OnyxAppleNativeEventKind.dismissed:
      return NativeTvClosed(
        byUser: event.reason != OnyxAppleNativeReason.requested,
      );
    case OnyxAppleNativeEventKind.unavailable:
      return NativeTvUnavailable(event.reason);
  }
}

NativeTvIntent? _menuIntent(String? menuId, String? optionId) {
  if (optionId == null) return null;
  switch (menuId) {
    case NativeTvIds.speed:
      final rate = double.tryParse(optionId);
      return rate == null ? null : NativeTvSetRate(rate);
    case NativeTvIds.fit:
      final mode = VideoDisplayMode.values
          .where((mode) => mode.name == optionId)
          .firstOrNull;
      return mode == null ? null : NativeTvSetFit(mode);
    case NativeTvIds.quality:
      if (optionId == NativeTvIds.qualityAuto) {
        return const NativeTvSetQuality(auto: true);
      }
      if (optionId == NativeTvIds.qualityDirect) {
        return const NativeTvSetQuality();
      }
      if (optionId.startsWith(NativeTvIds.qualityTierPrefix)) {
        return NativeTvSetQuality(
          key: optionId.substring(NativeTvIds.qualityTierPrefix.length),
        );
      }
      return null;
    case NativeTvIds.audio:
      if (optionId.startsWith(NativeTvIds.audioIndexPrefix)) {
        final index = int.tryParse(
          optionId.substring(NativeTvIds.audioIndexPrefix.length),
        );
        return index == null ? null : NativeTvSetAudio(serverIndex: index);
      }
      if (optionId.startsWith(NativeTvIds.audioTrackPrefix)) {
        return NativeTvSetAudio(
          engineTrackId:
              optionId.substring(NativeTvIds.audioTrackPrefix.length),
        );
      }
      return null;
  }
  return null;
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

  /// Le natif a refusé (`unavailable`) ou l'utilisateur l'a fermé : il ne se
  /// présente plus pour ce lecteur. Le représenter après un refus, c'était
  /// un aller-retour noir à chaque changement d'état.
  bool _retired = false;

  /// La raison du dernier `unavailable` : un refus vaut pour toute la vie de
  /// ce lecteur, et la règle de repli la reprend.
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
      _retired = true;
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
