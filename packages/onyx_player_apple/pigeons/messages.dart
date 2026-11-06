import 'package:pigeon/pigeon.dart';

/// Le contrat entre le lecteur Dart et AetherEngine.
///
/// C'est la seule source de vérité : les deux côtés sont générés à partir
/// d'ici. Après toute modification :
///
/// ```
/// dart run pigeon --input pigeons/messages.dart
/// dart run tool/sync_tvos.dart
/// ```
///
/// Le second pas n'est pas facultatif. Pigeon n'importe `Flutter` que sous
/// `os(iOS)`, ce qui laisse l'Apple TV sans le module ; le script corrige la
/// garde puis recopie les sources vers `tvos/`.
///
/// Ne rien écrire à la main dans `messages.g.dart` / `Messages.g.swift`.
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'darwin/onyx_player_apple/Sources/onyx_player_apple/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'onyx_player_apple',
  ),
)
/// Où en est le lecteur. Le même vocabulaire que sur Android, pour que les
/// deux sessions de l'app se lisent de la même façon.
enum OnyxApplePlaybackState {
  /// Rien de chargé, ou lecture arrêtée.
  idle,

  /// Ouverture, saut ou réserve vide : l'image n'avance pas en attendant des
  /// données.
  buffering,

  /// Prêt à jouer, ou en train de jouer.
  ready,

  /// Arrivé au bout. Terminal : il faut rouvrir pour relire.
  ended,
}

/// Pourquoi une ouverture a échoué.
///
/// Le détail porte une décision : un fichier que l'appareil ne sait pas lire
/// se rattrape par le transcodage du serveur, une source injoignable non.
enum OnyxApplePlayerErrorKind {
  unsupported,
  source,
  unknown,
}

/// Comment l'image occupe la vue.
///
/// C'est la couche vidéo qui cadre (`videoGravity`), pas la taille de la vue :
/// la vue garde celle de l'écran.
enum OnyxAppleVideoFit {
  /// L'image entière, avec des bandes s'il le faut.
  contain,

  /// La vue remplie, l'image rognée sur ce qui dépasse.
  cover,
}

/// Une piste qu'AetherEngine a énumérée.
class OnyxAppleTrack {
  OnyxAppleTrack({
    required this.id,
    required this.codec,
    required this.channels,
    required this.isDefault,
    required this.isForced,
    required this.isAtmos,
    required this.isBitmap,
    required this.isContainerStream,
    this.title,
    this.language,
  });

  /// L'index du flux dans le conteneur (`TrackInfo.id`), en texte : c'est ce
  /// que `PlaybackTrack.id` attend.
  final String id;
  final String? title;
  final String? language;

  /// Le nom libavcodec : `truehd`, `hdmv_pgs_subtitle`…
  final String codec;

  /// 0 pour une piste de sous-titres.
  final int channels;
  final bool isDefault;
  final bool isForced;

  /// E-AC-3 JOC : le lit d'objets passe tel quel jusqu'à la sortie.
  final bool isAtmos;

  /// Sous-titres image (PGS, VobSub, DVB), dessinés en bitmap.
  final bool isBitmap;

  /// Un vrai flux du conteneur. Faux pour un sous-titre externe posé par
  /// l'app, et pour les sous-titres CEA-608 que le moteur extrait de l'image :
  /// ni l'un ni l'autre n'a de place dans la numérotation des pistes du
  /// fichier, par laquelle le contrôleur retrouve leur langue.
  final bool isContainerStream;
}

class OnyxAppleVideoSize {
  OnyxAppleVideoSize({required this.width, required this.height});

  final int width;
  final int height;
}

/// Un instantané complet de l'état du lecteur.
///
/// Un seul objet plutôt qu'un événement par propriété, comme sur Android :
/// l'appelant n'a qu'un état à réconcilier.
class OnyxApplePlayerStatus {
  OnyxApplePlayerStatus({
    required this.playerId,
    required this.state,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.bufferedPositionMs,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.videoFormat,
    this.videoSize,
    this.pixelAspectRatio,
    this.selectedAudioTrackId,
    this.selectedSubtitleTrackId,
    this.errorKind,
    this.errorMessage,
    this.videoRoute,
  });

  final int playerId;
  final OnyxApplePlaybackState state;

  /// L'image avance réellement, distinct de « on lui a demandé de lire ».
  final bool isPlaying;

  final int positionMs;

  /// 0 tant que la sonde du conteneur n'a pas répondu.
  final int durationMs;

  final int bufferedPositionMs;

  /// Null tant que la sonde n'a pas donné les dimensions.
  final OnyxAppleVideoSize? videoSize;

  /// Les pixels non carrés d'un DVD ou d'un MPEG-2 anamorphosé. Null quand ils
  /// sont carrés.
  final double? pixelAspectRatio;

  final List<OnyxAppleTrack> audioTracks;
  final List<OnyxAppleTrack> subtitleTracks;
  final String? selectedAudioTrackId;
  final String? selectedSubtitleTrackId;

  /// Ce que l'écran présente : `sdr`, `hdr10`, `hdr10plus`, `dolbyvision`,
  /// `hlg`. Déjà ramené à ce que l'écran sait faire — un Dolby Vision sur un
  /// écran HDR10 se lit `hdr10`.
  final String videoFormat;

  final OnyxApplePlayerErrorKind? errorKind;
  final String? errorMessage;

  /// Le chemin vidéo du moteur (`loopback`, `software`, `remoteBypass`,
  /// `none`…). Sur `software`, il n'y a pas d'`AVPlayer` : l'écran natif
  /// d'Apple TV n'a rien à montrer et l'interface Flutter garde la main.
  final String? videoRoute;
}

/// Un fichier de sous-titres texte déclaré à l'ouverture
/// (`LoadOptions.externalSubtitles`).
///
/// Déclaré au chargement, il entre dans le groupe `legible` de l'item, donc
/// dans le menu Sous-titres d'AVKit. Posé après coup
/// ([OnyxApplePlayerApi.setExternalSubtitle]), il n'existe que pour la couche
/// de sous-titres de l'app.
class OnyxAppleExternalSubtitle {
  OnyxAppleExternalSubtitle({
    required this.url,
    required this.isForced,
    required this.isDefault,
    this.language,
    this.title,
  });

  /// Une URL absolue (avec son ticket de lecture), ou un chemin local.
  final String url;
  final String? language;
  final String? title;
  final bool isForced;
  final bool isDefault;
}

/// Les sous-titres que le moteur prépare pour le rendu natif à la prochaine
/// ouverture.
class OnyxAppleLoadSubtitles {
  OnyxAppleLoadSubtitles({required this.prepareNative, required this.external});

  /// `LoadOptions.prepareNativeSubtitles` : les pistes texte du fichier
  /// rejoignent le groupe `legible`, que l'écran natif d'Apple TV affiche.
  /// Les sous-titres image (PGS, VobSub, DVB) en restent exclus.
  final bool prepareNative;
  final List<OnyxAppleExternalSubtitle> external;
}

/// Un sous-titre image, placé en fractions de l'image vidéo.
///
/// Les fractions et non des pixels : la vue Flutter qui le peint n'a pas la
/// taille du canevas du PGS, et c'est elle qui sait où est l'image à l'écran.
class OnyxAppleSubtitleBitmap {
  OnyxAppleSubtitleBitmap({
    required this.png,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final Uint8List png;
  final double left;
  final double top;
  final double width;
  final double height;
}

/// Ce qu'il faut afficher comme sous-titres à cet instant.
///
/// Un flux à part du statut : il ne change qu'à chaque réplique, et une image
/// PGS n'a rien à faire dans un événement qui part quatre fois par seconde.
class OnyxAppleSubtitleFrame {
  OnyxAppleSubtitleFrame({
    required this.playerId,
    required this.lines,
    required this.bitmaps,
  });

  final int playerId;

  /// Les répliques texte, à peindre par la couche de sous-titres de l'app
  /// pour garder le même habillage partout.
  final List<String> lines;
  final List<OnyxAppleSubtitleBitmap> bitmaps;
}

/// Ce qu'AetherEngine sait dire de la lecture en cours, pour le journal.
class OnyxApplePlaybackStats {
  OnyxApplePlaybackStats({
    this.droppedFrames,
    this.observedFps,
    this.containerFps,
    this.videoCodec,
    this.videoDecoder,
    this.audioDecoder,
    this.videoBitrate,
    this.averageBitrateMbps,
    this.route,
    this.audioDelivery,
    this.container,
  });

  final int? droppedFrames;
  final double? observedFps;
  final double? containerFps;
  final String? videoCodec;
  final String? videoDecoder;
  final String? audioDecoder;

  /// Ce que le conteneur déclare, en bits par seconde.
  final int? videoBitrate;

  /// Ce qui a réellement transité depuis l'ouverture.
  final double? averageBitrateMbps;

  /// Le chemin qui sert la lecture : `loopback` (AVPlayer sur un remux local),
  /// `software` (décodage FFmpeg), `remoteBypass` (HLS du serveur lu tel
  /// quel). C'est la première chose à savoir d'une lecture qui chauffe.
  final String? route;

  /// `streamCopy`, `bridged`, `decoded`… : l'audio est-il passé tel quel.
  final String? audioDelivery;
  final String? container;
}

/// La fenêtre d'image dans l'image, quand le système l'ouvre ou la referme.
///
/// Le système décide seul du moment (geste d'accueil), donc c'est le natif qui
/// raconte, pas Dart qui demande. Voir l'ADR-0012.
class OnyxApplePictureInPicture {
  OnyxApplePictureInPicture({
    required this.playerId,
    required this.active,
    required this.closed,
  });

  final int playerId;

  /// Vrai tant que le film joue dans la petite fenêtre.
  final bool active;

  /// Vrai quand la fenêtre a été fermée au lieu d'être restaurée : le film n'a
  /// plus d'endroit où jouer, le natif l'a déjà mis en pause.
  final bool closed;
}

/// Une option d'un menu du lecteur natif (`UIAction` dans la barre de
/// transport d'AVKit).
class OnyxAppleNativeOption {
  OnyxAppleNativeOption({
    required this.id,
    required this.label,
    required this.selected,
    this.detail,
  });

  /// Rendu tel quel dans [OnyxAppleNativeEvent.optionId] au choix.
  final String id;

  /// Déjà traduit : Swift n'affiche que ce texte.
  final String label;

  /// Coché dans le menu. Dart reste maître de l'état : le natif ne coche rien
  /// de lui-même, il attend la spec suivante.
  final bool selected;

  /// Seconde ligne, déjà traduite (`UIMenuElement.subtitle`) : le codec d'une
  /// piste, « reste 12 min » d'une minuterie, l'avertissement Dolby Vision.
  final String? detail;
}

/// Un menu de la barre de transport : Vitesse, Format d'image, Qualité,
/// Audio et, au besoin, Sous-titres.
///
/// L'audio passe par ici et non par le menu AVKit : le moteur ne sert qu'une
/// rendition audio, donc AVKit n'expose que la piste active.
class OnyxAppleNativeMenu {
  OnyxAppleNativeMenu({
    required this.id,
    required this.label,
    required this.options,
    this.icon,
  });

  /// Identifiant stable choisi par Dart (`speed`, `fit`, `quality`, `audio`,
  /// `subtitles`), rendu dans [OnyxAppleNativeEvent.menuId].
  final String id;
  final String label;
  final List<OnyxAppleNativeOption> options;

  /// Le nom d'un symbole SF (`speedometer`, `4k.tv`…) posé devant le
  /// sous-menu dans le menu Réglages. Choisi par Dart, comme le reste.
  final String? icon;
}

/// Un bouton contextuel posé sur le lecteur : « Passer l'intro », « Épisode
/// suivant ». Dart ajoute ou retire l'entrée selon la position.
class OnyxAppleNativeAction {
  OnyxAppleNativeAction({required this.id, required this.label});

  /// Rendu dans [OnyxAppleNativeEvent.actionId] à l'appui.
  final String id;
  final String label;
}

/// Un chapitre, pour `AVPlayerItem.navigationMarkerGroups`
/// (`AVTimedMetadataGroup` : titre et plage).
class OnyxAppleNativeChapter {
  OnyxAppleNativeChapter({
    required this.title,
    required this.startMs,
    required this.endMs,
  });

  /// Déjà traduit (« Chapitre 3 » quand le fichier n'a pas de titre).
  final String title;
  final int startMs;
  final int endMs;
}

/// L'épisode suivant, proposé par une sous-classe d'`AVContentProposalViewController`.
/// Dart reste maître de l'enchaînement : le natif n'accepte jamais de lui-même.
class OnyxAppleNativeNextUp {
  OnyxAppleNativeNextUp({
    required this.title,
    required this.transitionMs,
    required this.playLabel,
    required this.laterLabel,
    this.subtitle,
    this.imageUrl,
    this.countdownSeconds,
  });

  /// « S1:E4 · Le titre ».
  final String title;
  final String? subtitle;

  /// L'image de l'épisode, en URL absolue avec son ticket.
  final String? imageUrl;

  /// `contentTimeForTransition` : le début du générique, en temps de l'item.
  final int transitionMs;

  /// Les secondes qui restent avant que Dart n'enchaîne, ou null sans compte
  /// à rebours (gelé, annulé, minuterie de veille).
  final int? countdownSeconds;

  /// « Lire » → action `nextEpisode` ; « Plus tard » → action
  /// `cancelAutoPlay`, après `dismissContentProposal(for: .defer)`.
  final String playLabel;
  final String laterLabel;
}

/// Une question posée par-dessus le lecteur natif : « Vous regardez encore ? »,
/// langue manquante, saison suivante, épisode à venir, lecture reprise ailleurs.
class OnyxAppleNativePrompt {
  OnyxAppleNativePrompt({
    required this.id,
    required this.title,
    required this.actions,
    required this.cancelActionId,
    this.message,
  });

  /// Stable d'une spec à l'autre : la même question n'est pas reposée.
  final String id;
  final String title;
  final String? message;

  /// Dans l'ordre d'affichage ; la première est l'action préférée.
  final List<OnyxAppleNativeAction> actions;

  /// L'action que vaut Menu (la touche Retour de la télécommande), rendue en
  /// `action`. Elle doit être l'une de [actions].
  final String cancelActionId;
}

/// Une ligne d'un panneau : un épisode, un participant, une statistique.
class OnyxAppleNativePanelRow {
  OnyxAppleNativePanelRow({
    required this.id,
    required this.title,
    required this.selected,
    required this.selectable,
    this.subtitle,
    this.detail,
    this.imageUrl,
    this.progress,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// À droite : une durée, « Hôte », une valeur de statistique.
  final String? detail;
  final String? imageUrl;

  /// Avancement de 0 à 1, pour un épisode commencé.
  final double? progress;

  /// L'épisode qui joue : marqué, et le focus y entre.
  final bool selected;

  /// Faux pour une ligne d'information (participant, statistique).
  final bool selectable;
}

/// Un onglet du panneau d'infos d'AVKit (`customInfoViewControllers`).
///
/// Un seul modèle pour Épisodes, Regarder ensemble et Stats : Swift a un seul
/// contrôleur à écrire.
class OnyxAppleNativePanel {
  OnyxAppleNativePanel({
    required this.id,
    required this.title,
    required this.tabs,
    required this.rows,
    required this.actions,
    required this.loading,
    this.message,
  });

  /// `episodes`, `watchParty`, `stats` : rendu dans les événements.
  final String id;

  /// Le titre de l'onglet (`UIViewController.title`).
  final String title;

  /// Un paragraphe au-dessus des lignes : l'explication et le code de la
  /// séance, une erreur.
  final String? message;

  /// Les saisons : un choix rendu en `panelTabSelected` (`optionId`).
  final List<OnyxAppleNativeOption> tabs;

  /// Pour `stats`, les lignes ne portent que l'identifiant de la mesure
  /// (`route`, `videoCodec`, `videoDecoder`, `audioDecoder`, `observedFps`,
  /// `containerFps`, `droppedFrames`, `averageBitrateMbps`, `videoBitrate`,
  /// `videoFormat`, `audioDelivery`, `container`) et son libellé : Swift
  /// remplit `detail` lui-même, chaque seconde, tant que l'onglet est visible.
  final List<OnyxAppleNativePanelRow> rows;

  /// Les boutons sous les lignes (« Démarrer une séance », « Quitter la
  /// séance »), rendus en `action`.
  final List<OnyxAppleNativeAction> actions;
  final bool loading;
}

/// Tout ce que le lecteur natif affiche, en un seul objet : Swift n'a pas
/// d'état à réconcilier, il applique la dernière spec reçue.
///
/// Tous les textes sont traduits côté Dart.
class OnyxAppleNativeSpec {
  OnyxAppleNativeSpec({
    required this.title,
    required this.settingsLabel,
    required this.menus,
    required this.actions,
    required this.chapters,
    required this.infoActions,
    required this.panels,
    required this.interceptSeeks,
    this.subtitle,
    this.posterUrl,
    this.overview,
    this.nextUp,
    this.prompt,
    this.toast,
  });

  final String title;
  final String? subtitle;

  /// L'affiche, en URL absolue (avec le ticket d'image s'il en faut un).
  final String? posterUrl;
  /// Le synopsis (`description` est réservé en Swift).
  final String? overview;

  /// Le titre du bouton Réglages (engrenage) qui porte [menus] dans la barre
  /// de transport. tvOS n'y montre que les éléments qui ont une image : posés
  /// à plat et sans icône, les menus n'apparaissaient pas du tout.
  final String settingsLabel;

  /// Les sous-menus du bouton Réglages : vitesse, format, qualité, audio…
  final List<OnyxAppleNativeMenu> menus;
  final List<OnyxAppleNativeAction> actions;

  /// `AVPlayerItem.navigationMarkerGroups`, reposé sur chaque nouvel item.
  final List<OnyxAppleNativeChapter> chapters;

  /// `infoViewActions` (deux au plus) : épisode précédent, épisode suivant.
  /// Vide, AVKit n'en montre aucune : pas de « Lire depuis le début », qui
  /// chercherait sans Dart.
  final List<OnyxAppleNativeAction> infoActions;

  /// L'épisode suivant proposé au générique (`AVContentProposal`), ou null.
  final OnyxAppleNativeNextUp? nextUp;

  /// La question à poser par-dessus le lecteur (`UIAlertController`), ou null.
  final OnyxAppleNativePrompt? prompt;

  /// Les onglets ajoutés au panneau d'infos (`customInfoViewControllers`),
  /// dans l'ordre : Épisodes, Regarder ensemble, Stats.
  final List<OnyxAppleNativePanel> panels;

  /// Une annonce en haut de l'image (`contentOverlayView`), ou null pour la
  /// retirer. Regarder ensemble l'utilise.
  final String? toast;

  /// Le natif retient les recherches de l'utilisateur au lieu de les
  /// appliquer, et les remonte en `seekRequested` : Dart décide (HLS, où une
  /// recherche peut reconstruire la session).
  final bool interceptSeeks;
}

/// Ce que le natif raconte à Dart.
enum OnyxAppleNativeEventKind {
  /// Un bouton contextuel a été pressé : [OnyxAppleNativeEvent.actionId].
  action,

  /// Une option de menu a été choisie : `menuId` et `optionId`.
  menuSelected,

  /// Un sous-titre a été choisi dans le menu AVKit : `trackId` (l'index de
  /// flux du moteur), nul pour « aucun ». Le moteur ne l'a pas adoptée :
  /// Dart doit rappeler `selectSubtitleTrack` pour que le choix tienne.
  subtitleSelected,

  /// L'écran natif est fermé : [OnyxAppleNativeEvent.reason].
  dismissed,

  /// Le natif ne sait pas jouer ceci : Dart doit rendre l'écran Flutter.
  /// [OnyxAppleNativeEvent.reason] dit pourquoi.
  unavailable,

  /// Lecture ou pause demandée dans AVKit (télécommande, Centre de contrôle,
  /// app Remote) : `playing`, `positionMs`. Jamais pour une demande de Dart.
  transport,

  /// L'utilisateur a déplacé la lecture dans AVKit (saut de 10 s, balayage,
  /// chapitre), déjà appliqué : `fromPositionMs`, `positionMs`.
  userSeeked,

  /// La même chose, retenue parce que `interceptSeeks` : Dart doit chercher
  /// `positionMs`.
  seekRequested,

  /// Une ligne choisie dans un panneau : `panelId`, `rowId`.
  panelRowSelected,

  /// Un onglet choisi dans un panneau (une saison) : `panelId`, `optionId`.
  panelTabSelected,

  /// Quelqu'un se sert de la télécommande : la barre de transport apparaît,
  /// un menu, une action ou une navigation. Au plus un toutes les 5 s.
  userActivity,
}

/// Pourquoi l'écran natif se ferme ou n'est pas disponible.
enum OnyxAppleNativeReason {
  /// Menu (télécommande) ou geste de fermeture.
  userDismissed,

  /// Dart a demandé la fermeture (`dismissNative`).
  requested,

  /// La route vidéo est `software` : `currentAVPlayer` est nul et AVKit
  /// n'afficherait qu'une roue sur fond noir, son joué.
  softwareRoute,

  /// La présentation a échoué (pas de contrôleur racine, lecteur inconnu).
  presentationFailed,

  /// Plateforme sans lecteur natif (iPhone, Mac).
  unsupported,

  /// Une piste image (PGS, VobSub, DVB) est active et l'écran natif n'a pas
  /// pu poser sa couche pour la peindre. Il se ferme ; ce n'est un refus que
  /// tant qu'une piste image reste choisie.
  bitmapSubtitles,
}

/// Un événement du lecteur natif. Un seul type pour tous : seuls les champs
/// de son [kind] sont remplis.
class OnyxAppleNativeEvent {
  OnyxAppleNativeEvent({
    required this.playerId,
    required this.kind,
    this.actionId,
    this.menuId,
    this.optionId,
    this.trackId,
    this.reason,
    this.playing,
    this.positionMs,
    this.fromPositionMs,
    this.panelId,
    this.rowId,
  });

  final int playerId;
  final OnyxAppleNativeEventKind kind;
  final String? actionId;
  final String? menuId;
  final String? optionId;
  final String? trackId;
  final OnyxAppleNativeReason? reason;

  /// `transport` : l'état demandé dans AVKit.
  final bool? playing;

  /// `transport`, `userSeeked`, `seekRequested` : la position en temps de
  /// l'item (millisecondes).
  final int? positionMs;

  /// `userSeeked` : d'où l'utilisateur est parti.
  final int? fromPositionMs;

  /// `panelRowSelected`, `panelTabSelected`.
  final String? panelId;

  /// `panelRowSelected`.
  final String? rowId;
}

@HostApi()
abstract class OnyxApplePlayerApi {
  /// Crée un lecteur et rend son identifiant. La vue s'y rattache par cet
  /// identifiant, ce qui permet d'ouvrir un média avant que la vue n'existe
  /// et de survivre à sa reconstruction.
  int create();

  /// Détruit le lecteur. Sans appel, AetherEngine garde sa connexion, son
  /// serveur local et son décodeur pour toute la vie du processus.
  void release(int playerId);

  /// Charge [url] (le fichier du serveur, un fichier téléchargé ou une
  /// session HLS) en se plaçant à [startPositionMs] dans le même geste.
  ///
  /// Rend la main tout de suite : l'ouverture et ses pannes arrivent par le
  /// flux d'état, comme sur Android.
  void open(int playerId, String url, int startPositionMs, bool play);

  void play(int playerId);

  void pause(int playerId);

  void seekTo(int playerId, int positionMs);

  /// Décharge le média sans détruire le lecteur.
  void stop(int playerId);

  void setVolume(int playerId, double volume);

  void setRate(int playerId, double rate);

  /// Le cadrage de l'image dans la vue. Tient d'une ouverture à l'autre.
  void setVideoFit(int playerId, OnyxAppleVideoFit fit);

  /// Quelle langue audio charger d'emblée, la plus probable en premier. Posé
  /// avant l'ouverture : après, changer de piste reconstruit la session
  /// (une demi-seconde d'image noire).
  void setPreferredAudioLanguages(int playerId, List<String> priorities);

  /// Les sous-titres à déclarer au chargement, appliqués à la prochaine
  /// ouverture et aux suivantes. AVKit ne voit que ceux-là : un WebVTT posé
  /// après coup n'arrive jamais dans son menu (spike Apple TV, Q5).
  void setLoadSubtitles(int playerId, OnyxAppleLoadSubtitles subtitles);

  void selectAudioTrack(int playerId, String trackId);

  /// Une piste de sous-titres du média, ou aucune si [trackId] est nul.
  void selectSubtitleTrack(int playerId, String? trackId);

  /// Pose (ou retire, avec null) le WebVTT que le serveur a produit.
  void setExternalSubtitle(
    int playerId,
    String? vttContent,
    String? language,
    String? title,
  );

  /// L'état à cet instant, pour s'amorcer sans attendre le premier événement.
  OnyxApplePlayerStatus status(int playerId);

  OnyxApplePlaybackStats stats(int playerId);

  /// Si l'appareil sait faire l'image dans l'image (iPhone et iPad ; ni Mac, ni
  /// Apple TV, où le lecteur n'en a pas l'usage).
  bool supportsPictureInPicture();

  /// Arme ou désarme la fenêtre pour ce lecteur. Armée, le système l'ouvre de
  /// lui-même quand l'utilisateur quitte l'app en cours de film : iOS ne
  /// laisse pas l'app la demander après coup, comme Android.
  void setPictureInPictureArmed(int playerId, bool armed);

  /// Présente l'`AVPlayerViewController` natif par-dessus Flutter (Apple TV
  /// seulement). Le lecteur doit déjà avoir ouvert un média. Si le natif ne
  /// sait pas faire, il répond par un événement `unavailable`, jamais par une
  /// erreur : Dart garde alors l'écran Flutter.
  void presentNative(int playerId, OnyxAppleNativeSpec spec);

  /// Remplace ce qu'affiche l'écran natif (menus cochés, action contextuelle
  /// apparue ou retirée, titre de l'épisode suivant). Sans effet s'il n'est
  /// pas présenté.
  void updateNative(int playerId, OnyxAppleNativeSpec spec);

  /// Ferme l'écran natif. Sans effet s'il n'est pas présenté ; le natif
  /// répond `dismissed` avec la raison `requested`.
  void dismissNative(int playerId);
}

@EventChannelApi()
abstract class OnyxApplePlayerEventApi {
  /// Un flux unique pour tous les lecteurs ; [OnyxApplePlayerStatus.playerId]
  /// dit lequel.
  OnyxApplePlayerStatus statusChanged();

  /// Les sous-titres à afficher, à chaque changement de réplique.
  OnyxAppleSubtitleFrame subtitlesChanged();

  /// L'ouverture et la fermeture de la fenêtre d'image dans l'image.
  OnyxApplePictureInPicture pictureInPictureChanged();

  /// Le journal d'AetherEngine, par paquets de lignes, pour le journal par
  /// lecture de l'app (ADR-0026). Les secrets (ticket de lecture) y sont
  /// déjà masqués.
  List<String> engineLog();

  /// Les actions de l'utilisateur sur l'écran natif et son repli, tous
  /// lecteurs confondus ; [OnyxAppleNativeEvent.playerId] dit lequel.
  OnyxAppleNativeEvent nativeEvents();
}
