import AVFoundation
import AetherEngine
import Combine
import CoreMedia
import Foundation

#if os(iOS)
  import AVKit

  /// La fenêtre d'image dans l'image d'un lecteur, sur iPhone et iPad.
  ///
  /// AetherEngine fournit la matière, pas le contrôleur : c'est à l'hôte de
  /// bâtir l'`AVPictureInPictureController`, autour de la couche AVPlayer
  /// quand la lecture passe par AVPlayer (`nativePlayerLayer`), ou autour de la
  /// couche d'images décodées quand c'est FFmpeg qui décode
  /// (`softwarePiPSource`). Les deux changent à chaque ouverture, d'où le
  /// contrôleur reconstruit quand la couche n'est plus la même.
  ///
  /// La fenêtre est *armée*, pas ouverte : iOS ne laisse pas l'app la demander
  /// après coup, c'est le système qui l'ouvre au geste d'accueil
  /// (`canStartPictureInPictureAutomaticallyFromInline`). Même contrat
  /// qu'Android, ADR-0012.
  @MainActor
  final class PictureInPictureBridge {
    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    private let engine: AetherEngine
    private let report: (_ active: Bool, _ closed: Bool) -> Void
    private let delegate = PictureInPictureDelegate()
    private var subscriptions = Set<AnyCancellable>()

    private var controller: AVPictureInPictureController?
    /// La couche autour de laquelle `controller` a été bâti.
    private var layerKey: ObjectIdentifier?
    private var armed = false
    private var refreshScheduled = false

    private var active = false
    /// L'utilisateur a touché « revenir à l'app » : la fin de la fenêtre qui
    /// suit est une restauration, pas une fermeture.
    private var restoring = false

    init(engine: AetherEngine, report: @escaping (_ active: Bool, _ closed: Bool) -> Void) {
      self.engine = engine
      self.report = report
      delegate.bridge = self

      // Les `@Published` émettent avant d'écrire : la couche n'est lisible qu'au
      // tour suivant.
      Publishers.Merge3(
        engine.$videoRoute.map { _ in () },
        engine.$softwarePiPSource.map { _ in () },
        engine.$hasFirstFrameReadyForDisplay.map { _ in () }
      )
      .sink { [weak self] in
        MainActor.assumeIsolated { self?.scheduleRefresh() }
      }
      .store(in: &subscriptions)
    }

    func setArmed(_ armed: Bool) {
      self.armed = armed
      controller?.canStartPictureInPictureAutomaticallyFromInline = armed
      if armed { scheduleRefresh() }
    }

    func release() {
      subscriptions.removeAll()
      drop()
    }

    // MARK: - Contrôleur

    private func scheduleRefresh() {
      guard !refreshScheduled else { return }
      refreshScheduled = true
      DispatchQueue.main.async { [weak self] in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.refreshScheduled = false
          self.refresh()
        }
      }
    }

    private func refresh() {
      // Une fenêtre ouverte garde son contrôleur : le passage à l'épisode
      // suivant la prolonge sur la même couche (moteur, AE#158), et la
      // reconstruire la fermerait sous les yeux de l'utilisateur.
      guard !active else { return }

      let nativeLayer = engine.nativePlayerLayer
      let software = engine.softwarePiPSource
      let key =
        nativeLayer.map(ObjectIdentifier.init) ?? software.map { ObjectIdentifier($0.layer) }
      guard key != layerKey else { return }

      drop()
      layerKey = key

      if let nativeLayer {
        controller = AVPictureInPictureController(playerLayer: nativeLayer)
      } else if let software {
        let source = AVPictureInPictureController.ContentSource(
          sampleBufferDisplayLayer: software.layer, playbackDelegate: delegate)
        controller = AVPictureInPictureController(contentSource: source)
      }
      controller?.delegate = delegate
      controller?.canStartPictureInPictureAutomaticallyFromInline = armed
    }

    private func drop() {
      controller?.delegate = nil
      controller = nil
      layerKey = nil
    }

    // MARK: - Ce que raconte le système

    fileprivate func willStart() {
      restoring = false
      // Avant que l'app ne passe en arrière-plan : c'est ce drapeau qui
      // empêche le moteur de couper l'image et l'audio.
      engine.pictureInPictureActive = true
    }

    fileprivate func didStart() {
      active = true
      report(true, false)
    }

    fileprivate func failedToStart() {
      active = false
      engine.pictureInPictureActive = false
    }

    fileprivate func willRestore() {
      restoring = true
    }

    fileprivate func didStop() {
      let closed = !restoring
      restoring = false
      active = false
      engine.pictureInPictureActive = false
      report(false, closed)
      // La couche a pu changer pendant la fenêtre (épisode suivant).
      scheduleRefresh()
    }

    // MARK: - Transport du chemin logiciel

    fileprivate func setPlaying(_ playing: Bool) {
      engine.softwarePiPSource?.setPlaying(playing)
    }

    fileprivate func skip(by seconds: Double) {
      engine.softwarePiPSource?.skip(by: seconds)
    }

    fileprivate var timeRange: CMTimeRange {
      engine.softwarePiPSource?.timeRange()
        ?? CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    fileprivate var isPaused: Bool {
      engine.softwarePiPSource?.isPaused ?? true
    }
  }

  /// Les rappels d'AVKit arrivent sur le thread principal mais ne sont pas
  /// isolés ; chacun le vérifie au lieu de le supposer, comme `PlayerHost`.
  private final class PictureInPictureDelegate: NSObject,
    AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate
  {
    weak var bridge: PictureInPictureBridge?

    func pictureInPictureControllerWillStartPictureInPicture(
      _ controller: AVPictureInPictureController
    ) {
      MainActor.assumeIsolated { bridge?.willStart() }
    }

    func pictureInPictureControllerDidStartPictureInPicture(
      _ controller: AVPictureInPictureController
    ) {
      MainActor.assumeIsolated { bridge?.didStart() }
    }

    func pictureInPictureController(
      _ controller: AVPictureInPictureController,
      failedToStartPictureInPictureWithError error: Error
    ) {
      MainActor.assumeIsolated { bridge?.failedToStart() }
    }

    func pictureInPictureController(
      _ controller: AVPictureInPictureController,
      restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
        @escaping (Bool) -> Void
    ) {
      MainActor.assumeIsolated { bridge?.willRestore() }
      // Flutter est déjà là : l'interface revient avec l'app.
      completionHandler(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(
      _ controller: AVPictureInPictureController
    ) {
      MainActor.assumeIsolated { bridge?.didStop() }
    }

    // MARK: AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(
      _ controller: AVPictureInPictureController, setPlaying playing: Bool
    ) {
      MainActor.assumeIsolated { bridge?.setPlaying(playing) }
    }

    func pictureInPictureControllerTimeRangeForPlayback(
      _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
      MainActor.assumeIsolated {
        bridge?.timeRange ?? CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
      }
    }

    func pictureInPictureControllerIsPlaybackPaused(
      _ controller: AVPictureInPictureController
    ) -> Bool {
      MainActor.assumeIsolated { bridge?.isPaused ?? true }
    }

    func pictureInPictureController(
      _ controller: AVPictureInPictureController,
      didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
      // Le moteur n'a rien à faire de la taille de la fenêtre.
    }

    func pictureInPictureController(
      _ controller: AVPictureInPictureController,
      skipByInterval skipInterval: CMTime,
      completion completionHandler: @escaping @Sendable () -> Void
    ) {
      MainActor.assumeIsolated { bridge?.skip(by: skipInterval.seconds) }
      completionHandler()
    }
  }
#else
  /// Ni le Mac, ni l'Apple TV n'ont l'usage de la petite fenêtre : un ordinateur
  /// a déjà des fenêtres, et le lecteur de la télévision n'a pas de chrome pour
  /// elle (ADR-0012, §4). Même interface, rien dedans, pour que `AetherPlayer`
  /// n'ait pas de branche par plateforme.
  @MainActor
  final class PictureInPictureBridge {
    static var isSupported: Bool { false }

    init(engine: AetherEngine, report: @escaping (_ active: Bool, _ closed: Bool) -> Void) {}

    func setArmed(_ armed: Bool) {}

    func release() {}
  }
#endif
