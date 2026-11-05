#if os(tvOS)
  import AVFoundation
  import AVKit
  import AetherEngine
  import Combine
  import UIKit

  /// Les sous-titres image (PGS, VobSub, DVB) sur l'écran natif de l'Apple TV.
  ///
  /// AVKit ne sait pas les peindre : le moteur les décode sur la route native
  /// comme ailleurs (`subtitleCues`, des `CGImage`), et cette couche les pose
  /// dans le `contentOverlayView`, entre l'image et la barre de transport. Rien
  /// ne passe par Dart : un aller-retour PNG par réplique, pour une interface
  /// Flutter qui n'est plus montée, ne servirait à rien.
  ///
  /// Le moteur donne aussi à chaque piste image une rendition texte reconnue
  /// par OCR, qu'il sélectionne dans le groupe `legible` tant que l'écran natif
  /// est là (`setNativeSubtitleRendering`). Elle sert au menu d'AVKit (la piste
  /// y est cochée), mais AVKit la peindrait par-dessus l'image : son rendu est
  /// coupé tant qu'une piste image est active.
  @MainActor
  final class NativeBitmapSubtitles {
    private let engine: AetherEngine
    private let onUnavailable: () -> Void
    private let view = NativeBitmapSubtitleView()
    private var attached = false
    private var reportedUnavailable = false

    private var subscriptions = Set<AnyCancellable>()
    private var refreshScheduled = false
    private var activeCues = ActiveCues()
    /// La sortie qui coupe le rendu `legible` d'AVKit, et l'item qui la porte :
    /// le moteur en crée un neuf à chaque rechargement (audio, qualité).
    private var suppression: (item: AVPlayerItem, output: AVPlayerItemLegibleOutput)?

    /// [onUnavailable] : une piste image est active et cette couche n'a pas pu
    /// se poser. Appelé une fois ; Dart reprend alors l'interface Flutter.
    init(engine: AetherEngine, onUnavailable: @escaping () -> Void) {
      self.engine = engine
      self.onUnavailable = onUnavailable
    }

    /// Le format d'image choisi, qui décide du cadre de la vidéo à l'écran.
    var gravity: AVLayerVideoGravity {
      get { view.gravity }
      set { view.gravity = newValue }
    }

    func attach(to controller: AVPlayerViewController) {
      controller.loadViewIfNeeded()
      if let overlay = controller.contentOverlayView {
        view.frame = overlay.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addSubview(view)
        attached = true
      }
      observe()
    }

    func detach() {
      subscriptions.removeAll()
      suppressNativeRendering(on: nil)
      activeCues.reset()
      view.show([])
      view.removeFromSuperview()
      attached = false
    }

    // MARK: - Moteur

    /// Les `@Published` émettent avant d'écrire : tout se relit au tour
    /// suivant, et les signaux d'un même tour n'en font qu'une lecture.
    /// L'horloge tourne à 10 Hz, comme pour les répliques envoyées à Dart.
    private func observe() {
      subscriptions.removeAll()
      let changes: [AnyPublisher<Void, Never>] = [
        Self.signal(engine.$subtitleCues),
        Self.signal(engine.clock.$sourceTime),
        Self.signal(engine.$activeSubtitleTrackIndex),
        Self.signal(engine.$subtitleTracks),
        Self.signal(engine.$currentAVPlayerItem),
        Self.signal(engine.$sourceVideoWidth),
        Self.signal(engine.$sourceVideoHeight),
      ]
      Publishers.MergeMany(changes)
        .sink { [weak self] _ in
          MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        .store(in: &subscriptions)
    }

    private static func signal<P: Publisher>(_ publisher: P) -> AnyPublisher<Void, Never>
    where P.Failure == Never {
      publisher.map { _ in () }.eraseToAnyPublisher()
    }

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
      guard !subscriptions.isEmpty else { return }
      let bitmapActive = NativeBitmapSubtitleLayout.isBitmap(
        engine.activeSubtitleTrackIndex, in: engine.subtitleTracks)
      guard attached || !bitmapActive else {
        if !reportedUnavailable {
          reportedUnavailable = true
          NSLog("Onyx: pas de contentOverlayView, sous-titres image rendus à Flutter")
          onUnavailable()
        }
        return
      }
      suppressNativeRendering(on: bitmapActive ? engine.currentAVPlayerItem : nil)

      let par = engine.sourceVideoPixelAspectRatio
      view.video = NativeBitmapSubtitleLayout.Video(
        codedSize: CGSize(width: Int(engine.sourceVideoWidth), height: Int(engine.sourceVideoHeight)),
        pixelAspect: par.isFinite && par > 0 ? par : 1)
      guard let active = activeCues.update(engine.subtitleCues, at: engine.clock.sourceTime) else { return }
      // Une piste texte active n'a que des répliques texte, qu'AVKit peint
      // lui-même : il ne reste alors rien à poser ici.
      view.show(
        active.compactMap { cue in
          if case .image(let image) = cue.body { return image }
          return nil
        })
    }

    /// Une sortie `legible` qui coupe le rendu du lecteur : la sélection reste
    /// (la coche du menu AVKit), seule la peinture d'AVKit disparaît. Les
    /// autres médias de l'item ne sont pas touchés (en-tête
    /// `AVPlayerItemOutput.suppressesPlayerRendering`).
    private func suppressNativeRendering(on item: AVPlayerItem?) {
      if let suppression, suppression.item === item { return }
      if let suppression { suppression.item.remove(suppression.output) }
      suppression = nil
      guard let item else { return }
      let output = AVPlayerItemLegibleOutput()
      output.suppressesPlayerRendering = true
      item.add(output)
      suppression = (item, output)
    }
  }

  /// Les images à l'écran, chacune dans son calque, recalées sur le cadre de
  /// la vidéo à chaque mise en page.
  final class NativeBitmapSubtitleView: UIView {
    var gravity: AVLayerVideoGravity = .resizeAspect {
      didSet { if oldValue != gravity { setNeedsLayout() } }
    }
    var video = NativeBitmapSubtitleLayout.Video(codedSize: .zero, pixelAspect: 1) {
      didSet { if oldValue != video { setNeedsLayout() } }
    }

    private var images: [SubtitleImage] = []
    private var imageLayers: [CALayer] = []

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }

    func show(_ images: [SubtitleImage]) {
      self.images = images
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      while imageLayers.count < images.count {
        let sublayer = CALayer()
        sublayer.contentsGravity = .resize
        sublayer.minificationFilter = .trilinear
        layer.addSublayer(sublayer)
        imageLayers.append(sublayer)
      }
      while imageLayers.count > images.count {
        imageLayers.removeLast().removeFromSuperlayer()
      }
      for (sublayer, image) in zip(imageLayers, images) {
        sublayer.contents = image.cgImage
      }
      CATransaction.commit()
      setNeedsLayout()
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      let rect = NativeBitmapSubtitleLayout.videoRect(video, in: bounds, gravity: gravity)
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      for (sublayer, image) in zip(imageLayers, images) {
        let frame = NativeBitmapSubtitleLayout.frame(
          position: image.position, canvas: image.canvasSize, video: video, in: rect)
        sublayer.isHidden = frame == nil
        sublayer.frame = frame ?? .zero
      }
      CATransaction.commit()
    }
  }

  /// Où poser une image : des fonctions pures, de la taille de la vidéo et de
  /// la vue jusqu'au cadre de chaque réplique.
  enum NativeBitmapSubtitleLayout {
    struct Video: Equatable {
      /// La taille de l'image décodée, en pixels du fichier.
      var codedSize: CGSize
      /// Largeur d'un pixel sur sa hauteur (DVD anamorphosé : plus de 1).
      var pixelAspect: Double
    }

    /// Une piste image : elle n'a que des images, qu'AVKit ne peint pas.
    static func isBitmap(_ trackId: Int?, in tracks: [TrackInfo]) -> Bool {
      guard let trackId, let track = tracks.first(where: { $0.id == trackId }) else { return false }
      return StatusMapping.bitmapSubtitleCodecs.contains(track.codec)
    }

    /// Le cadre de la vidéo dans [bounds], comme `AVPlayerLayer` le calcule
    /// pour [gravity]. `videoBounds` n'existe pas sur tvOS (en-tête
    /// `AVPlayerViewController.h`).
    static func videoRect(_ video: Video, in bounds: CGRect, gravity: AVLayerVideoGravity) -> CGRect {
      let width = video.codedSize.width * video.pixelAspect
      let height = video.codedSize.height
      guard width > 0, height > 0, bounds.width > 0, bounds.height > 0, gravity != .resize else {
        return bounds
      }
      let fit = min(bounds.width / width, bounds.height / height)
      let fill = max(bounds.width / width, bounds.height / height)
      let scale = gravity == .resizeAspectFill ? fill : fit
      let size = CGSize(width: width * scale, height: height * scale)
      return CGRect(
        x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
        width: size.width, height: size.height)
    }

    /// Le cadre d'une image placée en pixels du canevas (origine en haut à
    /// gauche, comme le PGS), ou nil si rien ne permet de la placer.
    ///
    /// Le canevas s'aligne sur la largeur de la vidéo et se centre en hauteur :
    /// un rip recadré garde un canevas 1920×1080 sur une image 1920×800, et la
    /// réplique doit tomber là où le disque l'a mise (README AetherEngine,
    /// `SubtitleImage.canvasSize`). Ses pixels ont le rapport de ceux de la
    /// vidéo : un DVD 720×576 en 16:9 s'étire comme son image. Sans canevas
    /// déclaré, c'est l'image décodée.
    static func frame(position: CGRect, canvas: CGSize, video: Video, in rect: CGRect) -> CGRect? {
      let canvas = canvas.width > 0 && canvas.height > 0 ? canvas : video.codedSize
      guard canvas.width > 0, canvas.height > 0, rect.width > 0, rect.height > 0 else { return nil }
      let scaleX = rect.width / canvas.width
      let scaleY = scaleX / video.pixelAspect
      let top = rect.midY - canvas.height * scaleY / 2
      return CGRect(
        x: rect.minX + position.minX * scaleX, y: top + position.minY * scaleY,
        width: position.width * scaleX, height: position.height * scaleY)
    }
  }
#endif
