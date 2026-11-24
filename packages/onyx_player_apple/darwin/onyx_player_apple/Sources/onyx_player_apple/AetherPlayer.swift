import AVFoundation
import AetherEngine
import Combine
import CoreGraphics
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#endif

/// Un lecteur : une instance d'AetherEngine, et ce qu'il faut pour la
/// raconter à Dart.
///
/// Toute la logique de lecture (reprise, sessions HLS, choix des pistes par
/// défaut) appartient au contrôleur de l'app. Ce type ne fait que traduire :
/// des commandes vers le moteur, des changements du moteur vers des
/// instantanés d'état.
@MainActor
final class AetherPlayer {
  let id: Int64
  let engine: AetherEngine

  /// Appliqué à la prochaine ouverture. Changer d'audio après coup reconstruit
  /// la session HLS locale (le moteur n'y sert qu'une rendition audio, pas de
  /// groupe `AVMediaSelection` à basculer) : image tenue mais ~1 s d'attente
  /// et un son qui repart. Voir ADR-0092.
  var preferredAudioLanguages: [String] = []

  private let onStatus: (OnyxApplePlayerStatus) -> Void
  private let onSubtitles: (OnyxAppleSubtitleFrame) -> Void
  private let onPictureInPicture: (OnyxApplePictureInPicture) -> Void
  private var pictureInPicture: PictureInPictureBridge?
  private var subscriptions = Set<AnyCancellable>()

  private var loadTask: Task<Void, Never>?

  /// Une ouverture qui a levé une erreur sans que le moteur passe en `.error`
  /// (une URL refusée avant toute session, par exemple). Sans elle, l'app
  /// attendrait la fin de son délai de démarrage sans savoir pourquoi.
  private var loadFailure: String?
  /// Le dernier play/pause demandé pendant un chargement. Le contrôleur ouvre
  /// en pause puis appelle play() tout de suite ; le moteur ignore un play
  /// arrivé avant la fin de `load`, et la lecture restait en pause.
  private var wantsPlay = false
  /// Où reprend la session en cours de reconstruction. Le moteur remet son
  /// horloge à zéro le temps de reconstruire : rapportée telle quelle, la
  /// barre de lecture retombait au début, et une reconstruction qui échoue
  /// faisait rouvrir le film à la seconde zéro.
  private var restoringAtMs: Int64?
  private let fastStart = FastStart()

  private var statusScheduled = false
  private var subtitlesScheduled = false
  private var activeCues = ActiveCues()

  /// Le WebVTT du serveur, écrit dans un fichier parce qu'AetherEngine ne prend
  /// des sous-titres externes que par URL.
  private var externalSubtitle: (trackId: Int, file: URL)?

  private var released = false

  init(
    id: Int64,
    onStatus: @escaping (OnyxApplePlayerStatus) -> Void,
    onSubtitles: @escaping (OnyxAppleSubtitleFrame) -> Void,
    onPictureInPicture: @escaping (OnyxApplePictureInPicture) -> Void
  ) throws {
    self.id = id
    self.engine = try AetherEngine()
    self.onStatus = onStatus
    self.onSubtitles = onSubtitles
    self.onPictureInPicture = onPictureInPicture
    observe()
    pictureInPicture = PictureInPictureBridge(engine: engine) { [weak self] active, closed in
      self?.pictureInPictureChanged(active: active, closed: closed)
    }
  }

  // MARK: - Commandes

  func open(_ url: String, startMs: Int64, play: Bool) throws {
    guard let source = Self.sourceURL(url) else {
      throw PigeonError(code: "bad_url", message: "URL de lecture illisible", details: nil)
    }
    Self.registerSecrets(of: source)

    loadTask?.cancel()
    loadFailure = nil
    // Une ouverture vide le registre des pistes externes du moteur : le
    // fichier de l'ancienne ne sert plus à rien.
    forgetExternalSubtitle()
    clearSubtitleFrame()

    wantsPlay = play
    var options = LoadOptions(preferredAudioLanguages: preferredAudioLanguages, autoplay: play)
    // La sonde FFmpeg lit par défaut jusqu'à 50 Mo pour dimensionner les
    // sous-titres PGS, dont le premier paquet peut être loin : sur un remux 4K
    // servi à ~50 Mb/s, c'était 5 s de démarrage sur 12. Les pistes PGS restent
    // listées (le MKV les déclare) ; seule leur taille est résolue plus tard.
    options.probesize = 8 * 1024 * 1024
    options.maxAnalyzeDuration = 5_000_000
    // Un seul GET tenu en HTTP/1.1 sur TCP pour le fichier brut. Par défaut, le
    // moteur rouvre une requête tous les 32 Mo et URLSession passe en HTTP/3
    // derrière Cloudflare : mesuré à ~60 Mb/s sur un lien qui en tient bien
    // plus, un remux 4K à 52 Mb/s se mettait en tampon toutes les 20 s. mpv,
    // en TCP sur une seule connexion, le lisait sans à-coup. Le HLS de
    // transcodage garde le transport par défaut : ce sont de petits segments.
    let isRawFile = source.pathExtension.lowercased() != "m3u8"
    options.heldSourceConnection = isRawFile
    // Le premier segment d'un remux 4K pèse ~15 Mo : mesuré 1,1 s d'attente
    // avant son premier octet (journal macOS 1.1.26, `seg575 wait=1102.8ms`),
    // parce que la boucle locale ne répond qu'une fois le segment coupé. En
    // progressif, elle envoie chaque fragment (~0,5 s) dès qu'il est écrit.
    // Le HLS de transcodage du serveur n'est pas concerné : AVPlayer parle
    // directement au serveur. Voir ADR-0092.
    options.progressiveSegmentDelivery = isRawFile
    // Une session HLS du serveur va droit à AVPlayer. Sans ceci, le moteur
    // tente d'abord de la démultiplexer comme un fichier, échoue (FFmpeg ne
    // lit pas une playlist ici), relit la playlist et télécharge la tête du
    // premier segment pour vérifier qu'il n'est pas du HEVC en MPEG-TS, puis
    // seulement la confie à AVPlayer, qui redemande le tout. Le serveur
    // n'envoie à ce client que du fMP4 : la vérification ne trouve jamais
    // rien, et chaque changement de qualité payait ces allers-retours, plus
    // l'attente d'un segment que le transcodage n'a pas encore écrit.
    options.nativeRemoteHLS = !isRawFile
    let loadOptions = options
    let start: Double? = startMs > 0 ? Double(startMs) / 1000 : nil
    loadTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.engine.load(url: source, startPosition: start, options: loadOptions)
        guard !Task.isCancelled else { return }
        self.loadTask = nil
        if self.wantsPlay != play {
          if self.wantsPlay { self.engine.play() } else { self.engine.pause() }
        }
      } catch is CancellationError {
        // Deux causes pour une même erreur, et ni l'une ni l'autre n'est une
        // panne. Notre tâche annulée : une ouverture plus récente ou un stop
        // l'a remplacée, et c'est elle qui tient la suite.
        guard !Task.isCancelled else { return }
        // Sinon c'est le moteur qui a remplacé ce chargement par sa propre
        // reconstruction : une piste audio choisie pendant l'ouverture
        // (`selectAudioTrack` reconstruit la session, ADR-0093). `load` ne
        // rendra jamais la main, et la session revient en pause. Sans ceci,
        // `loadTask` restait posé pour toujours : chaque play() de Dart était
        // retenu pour une fin de chargement qui ne viendrait plus, et l'écran
        // attendait son délai de démarrage devant une session prête (journal
        // iOS 1.1.52 : `load superseded (gen 1 -> 2)` puis
        // `reload: state=.paused`, plus rien).
        self.loadTask = nil
        self.deliverWantedTransport()
      } catch {
        guard !Task.isCancelled else { return }
        self.loadTask = nil
        self.loadFailure = error.localizedDescription
        self.scheduleStatus()
      }
    }
    fastStart.arm(engine: engine) { [weak self] in self?.wantsPlay ?? false }
    scheduleStatus()
  }

  func play() {
    wantsPlay = true
    // Une session démontée en arrière-plan n'a plus rien à lire : elle se
    // reconstruit d'abord, et le play est porté à la fin.
    restoreAfterBackground()
    if loadTask == nil { engine.play() }
  }

  func pause() {
    wantsPlay = false
    if loadTask == nil { engine.pause() }
  }

  /// Porte au moteur le dernier play/pause retenu pendant un chargement que
  /// le moteur a repris à son compte. Une reconstruction encore en cours le
  /// note et revient dans cet état ; une reconstruction finie l'applique tout
  /// de suite.
  private func deliverWantedTransport() {
    if wantsPlay { engine.play() } else { engine.pause() }
  }

  /// Reconstruit la session que le moteur a démontée quand l'app est passée
  /// en arrière-plan.
  ///
  /// Sur l'Apple TV, tout passage en arrière-plan (l'économiseur d'écran
  /// derrière une pause, le bouton TV, la veille) fait libérer au moteur son
  /// item AVPlayer et sa boucle locale, et le laisse en `.paused` : il attend
  /// de l'hôte qu'il le reconstruise au retour (`needsForegroundVideoRestore`).
  /// Personne ne le faisait. `engine.play()` passait alors l'état à `.playing`
  /// sur un lecteur sans item : la phase restait `.loading`, rien ne démarrait,
  /// et chaque appui alternait entre un sablier et une pause sans jamais
  /// relancer le film. Sur iPhone, même panne après plus de 15 s d'une pause
  /// en arrière-plan.
  ///
  /// Le dernier play/pause demandé est retenu pendant la reconstruction, comme
  /// pendant une ouverture, puis porté au moteur : la session revient dans
  /// l'état voulu, pas dans celui de son premier montage.
  ///
  /// Jamais tant que l'app est encore en arrière-plan (une séance partagée y
  /// envoie des play et des recherches) : le moteur démonte justement pour
  /// qu'aucun décodeur ne traverse la mise en veille de l'Apple TV.
  private func restoreAfterBackground(at positionMs: Int64? = nil) {
    guard !released, loadTask == nil, engine.needsForegroundVideoRestore, !isInBackground
    else { return }
    restoringAtMs = positionMs ?? StatusMapping.milliseconds(engine.clock.currentTime)
    loadTask = Task { [weak self] in
      guard let self else { return }
      defer { self.restoringAtMs = nil }
      do {
        try await self.engine.reloadAtCurrentPosition()
        guard !Task.isCancelled else { return }
        self.loadTask = nil
        self.deliverWantedTransport()
      } catch is CancellationError {
        // Comme à l'ouverture : notre tâche annulée laisse la suite à ce qui
        // l'a remplacée ; une reprise par le moteur reçoit la demande.
        guard !Task.isCancelled else { return }
        self.loadTask = nil
        self.deliverWantedTransport()
      } catch {
        guard !Task.isCancelled else { return }
        self.loadTask = nil
        self.loadFailure = error.localizedDescription
        self.scheduleStatus()
      }
    }
    scheduleStatus()
  }

  private var isInBackground: Bool {
    #if os(iOS) || os(tvOS)
      return UIApplication.shared.applicationState == .background
    #else
      return false
    #endif
  }

  func seek(toMs positionMs: Int64) {
    let seconds = Double(max(positionMs, 0)) / 1000
    Task { await engine.seek(to: seconds) }
    // Sur une session démontée, le moteur ne fait que noter la cible : c'est
    // la reconstruction qui y mène, dans un ordre ou dans l'autre.
    restoreAfterBackground(at: max(positionMs, 0))
  }

  func setPictureInPictureArmed(_ armed: Bool) {
    pictureInPicture?.setArmed(armed)
  }

  private func pictureInPictureChanged(active: Bool, closed: Bool) {
    // Fermer la petite fenêtre, c'est renoncer à regarder : un film qui n'a
    // plus d'écran ne doit pas continuer à jouer (ADR-0012, §2).
    if closed { pause() }
    onPictureInPicture(OnyxApplePictureInPicture(playerId: id, active: active, closed: closed))
  }

  /// Décharge le média sans toucher au mode de l'écran : l'épisode suivant
  /// arrive souvent juste derrière, et un téléviseur qui repasse en SDR entre
  /// deux épisodes HDR, c'est deux écrans noirs de plus.
  func stop() {
    fastStart.cancel()
    loadTask?.cancel()
    loadTask = nil
    loadFailure = nil
    forgetExternalSubtitle()
    engine.stop(resetDisplayCriteria: false, finalTeardown: false)
    clearSubtitleFrame()
    scheduleStatus()
  }

  /// La vraie fin : le mode de l'écran est rendu, l'audio aussi.
  func release() {
    released = true
    fastStart.cancel()
    loadTask?.cancel()
    forgetExternalSubtitle()
    subscriptions.removeAll()
    pictureInPicture?.release()
    pictureInPicture = nil
    engine.stop()
  }

  func selectAudioTrack(_ trackId: String) throws {
    let index = try Self.streamIndex(trackId)
    engine.selectAudioTrack(index: index)
  }

  func selectSubtitleTrack(_ trackId: String?) throws {
    guard let trackId else {
      engine.clearSubtitle()
      return
    }
    let index = try Self.streamIndex(trackId)
    engine.selectSubtitleTrack(index: index)
  }

  func setExternalSubtitle(_ vtt: String?, language: String?, title: String?) throws {
    forgetExternalSubtitle()
    guard let vtt else {
      engine.clearSubtitle()
      return
    }
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("onyx-subtitles-\(id)-\(UUID().uuidString).vtt")
    try vtt.write(to: file, atomically: true, encoding: .utf8)
    let track = engine.addExternalSubtitleTrack(
      ExternalSubtitleTrack(url: file, name: title, language: language, formatHint: "webvtt"))
    externalSubtitle = (track.id, file)
    engine.selectSubtitleTrack(index: track.id)
  }

  private func forgetExternalSubtitle() {
    guard let external = externalSubtitle else { return }
    externalSubtitle = nil
    engine.removeExternalSubtitleTrack(id: external.trackId)
    try? FileManager.default.removeItem(at: external.file)
  }

  // MARK: - État

  func snapshot() -> OnyxApplePlayerStatus {
    let phase = engine.playbackPhase
    let width = Int64(engine.sourceVideoWidth)
    let height = Int64(engine.sourceVideoHeight)
    let pixelAspect = engine.sourceVideoPixelAspectRatio

    var errorKind: OnyxApplePlayerErrorKind?
    var errorMessage: String?
    if case .error(let message) = phase {
      errorKind = engine.errorInfo.map { StatusMapping.errorKind($0.kind) } ?? .unknown
      errorMessage = engine.errorInfo?.message ?? message
    } else if let loadFailure {
      errorKind = engine.errorInfo.map { StatusMapping.errorKind($0.kind) } ?? .unknown
      errorMessage = loadFailure
    }

    return OnyxApplePlayerStatus(
      playerId: id,
      state: loadFailure != nil ? .idle : StatusMapping.state(phase),
      isPlaying: StatusMapping.isPlaying(phase),
      positionMs: StatusMapping.milliseconds(engine.clock.currentTime),
      durationMs: StatusMapping.milliseconds(engine.duration),
      bufferedPositionMs: StatusMapping.milliseconds(engine.clock.bufferedPosition),
      videoSize: width > 0 && height > 0 ? OnyxAppleVideoSize(width: width, height: height) : nil,
      pixelAspectRatio: pixelAspect.isFinite && pixelAspect > 0 && pixelAspect != 1 ? pixelAspect : nil,
      audioTracks: engine.audioTracks.map(StatusMapping.track),
      subtitleTracks: engine.subtitleTracks.map(StatusMapping.track),
      selectedAudioTrackId: engine.activeAudioTrackIndex.map { String($0) },
      selectedSubtitleTrackId: engine.activeSubtitleTrackIndex.map { String($0) },
      videoFormat: StatusMapping.videoFormat(engine.videoFormat),
      errorKind: errorKind,
      errorMessage: errorMessage,
      videoRoute: engine.videoRoute.rawValue,
      firstFrameShown: engine.hasFirstFrameReadyForDisplay)
  }

  func stats() -> OnyxApplePlaybackStats {
    let telemetry = engine.liveTelemetry
    return OnyxApplePlaybackStats(
      droppedFrames: telemetry?.droppedFrameCount.map { Int64($0) },
      observedFps: telemetry?.observedFps,
      containerFps: engine.sourceVideoFrameRate,
      videoCodec: engine.sourceVideoCodecName,
      videoDecoder: engine.activeVideoDecoder,
      audioDecoder: engine.activeAudioDecoder,
      videoBitrate: engine.sourceVideoBitrate > 0 ? engine.sourceVideoBitrate : nil,
      averageBitrateMbps: telemetry?.averageBitrateMbps,
      route: engine.videoRoute.rawValue,
      audioDelivery: engine.audioDelivery.rawValue,
      container: engine.sourceContainerFormat)
  }

  // MARK: - Observation

  /// Chaque changement du moteur demande un instantané ; les demandes d'un
  /// même tour de boucle n'en font partir qu'un.
  ///
  /// Les `@Published` émettent *avant* d'écrire la nouvelle valeur :
  /// l'instantané part donc au tour suivant, quand elle est en place. L'horloge
  /// tourne à 10 Hz ; quatre positions par seconde suffisent à la barre de
  /// lecture, comme sur Android.
  private func observe() {
    let tick = RunLoop.main
    let changes: [AnyPublisher<Void, Never>] = [
      Self.signal(engine.$playbackPhase),
      Self.signal(engine.$duration),
      Self.signal(engine.$audioTracks),
      Self.signal(engine.$subtitleTracks),
      Self.signal(engine.$activeAudioTrackIndex),
      Self.signal(engine.$activeSubtitleTrackIndex),
      Self.signal(engine.$errorInfo),
      Self.signal(engine.$sourceVideoWidth),
      Self.signal(engine.$sourceVideoHeight),
      Self.signal(engine.$videoFormat),
      Self.signal(engine.$videoRoute),
      Self.signal(engine.$hasFirstFrameReadyForDisplay),
      Self.signal(engine.clock.$currentTime.throttle(for: .milliseconds(250), scheduler: tick, latest: true)),
      Self.signal(engine.clock.$bufferedPosition.throttle(for: .milliseconds(250), scheduler: tick, latest: true)),
    ]
    Publishers.MergeMany(changes)
      .sink { [weak self] _ in
        MainActor.assumeIsolated { self?.scheduleStatus() }
      }
      .store(in: &subscriptions)

    Publishers.Merge(Self.signal(engine.$subtitleCues), Self.signal(engine.clock.$sourceTime))
      .sink { [weak self] _ in
        MainActor.assumeIsolated { self?.scheduleSubtitles() }
      }
      .store(in: &subscriptions)
  }

  private static func signal<P: Publisher>(_ publisher: P) -> AnyPublisher<Void, Never>
  where P.Failure == Never {
    publisher.map { _ in () }.eraseToAnyPublisher()
  }

  private func scheduleStatus() {
    guard !statusScheduled, !released else { return }
    statusScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.statusScheduled = false
        guard !self.released else { return }
        var status = self.snapshot()
        if let held = self.restoringAtMs { status.positionMs = held }
        self.onStatus(status)
      }
    }
  }

  private func scheduleSubtitles() {
    guard !subtitlesScheduled, !released else { return }
    subtitlesScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.subtitlesScheduled = false
        guard !self.released else { return }
        self.emitSubtitles()
      }
    }
  }

  private func emitSubtitles() {
    guard let active = activeCues.update(engine.subtitleCues, at: engine.clock.sourceTime) else { return }
    let canvas = CGSize(width: Int(engine.sourceVideoWidth), height: Int(engine.sourceVideoHeight))
    onSubtitles(SubtitleFrames.frame(playerId: id, cues: active, canvas: canvas))
  }

  /// Efface ce qui est à l'écran, une fois. Une réplique restée affichée par-
  /// dessus le film suivant est le genre de reste qu'on remarque tout de suite.
  private func clearSubtitleFrame() {
    guard !activeCues.ids.isEmpty else { return }
    activeCues.reset()
    onSubtitles(OnyxAppleSubtitleFrame(playerId: id, lines: [], bitmaps: []))
  }

  // MARK: - Sources

  /// Le fichier du serveur, une session HLS, ou un chemin local : l'app passe
  /// un fichier téléchargé comme un chemin nu, que mpv acceptait tel quel.
  static func sourceURL(_ value: String) -> URL? {
    if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
    guard let url = URL(string: value), url.scheme != nil else { return nil }
    return url
  }

  /// Le ticket de lecture voyage dans l'URL. AetherEngine journalise ses URL :
  /// sans ceci, le journal exporté par l'utilisateur le contiendrait en clair.
  static func registerSecrets(of url: URL) {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    for item in items where item.name == "ticket" {
      if let value = item.value { EngineLog.registerSecret(value) }
    }
  }

  static func streamIndex(_ trackId: String) throws -> Int {
    guard let index = Int(trackId) else {
      throw PigeonError(code: "bad_track", message: "Piste inconnue : \(trackId)", details: nil)
    }
    return index
  }
}
