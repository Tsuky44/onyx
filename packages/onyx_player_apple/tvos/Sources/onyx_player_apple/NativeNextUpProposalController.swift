#if os(tvOS)
  import AVFoundation
  import AVKit
  import CoreMedia
  import UIKit

  /// L'épisode suivant au générique, sur l'écran natif : une `AVContentProposal`
  /// posée sur l'item, présentée par `NativeNextUpProposalController`.
  ///
  /// Dart reste seul maître de l'enchaînement (question de langue, minuterie
  /// de veille, séance partagée) : la proposition n'est jamais acceptée
  /// d'elle-même, elle n'affiche que le compte à rebours de Dart et lui
  /// renvoie le choix de l'utilisateur.
  @MainActor
  final class NativeNextUp {
    /// Les actions que Dart connaît déjà (`NativeTvIds`).
    static let playActionId = "nextEpisode"
    static let laterActionId = "cancelAutoPlay"

    let controller = NativeNextUpProposalController()
    private let onPlay: () -> Void
    private let onLater: () -> Void

    private var current: OnyxAppleNativeNextUp?
    private weak var item: AVPlayerItem?
    /// L'utilisateur a répondu à cette proposition : un rechargement de l'item
    /// (audio, qualité) ne doit pas la reposer.
    private var answered = false
    private var image: (url: String, image: UIImage)?
    private var imageTask: Task<Void, Never>?
    private var imageRequested: String?

    init(onPlay: @escaping () -> Void, onLater: @escaping () -> Void) {
      self.onPlay = onPlay
      self.onLater = onLater
      controller.onPlay = { [weak self] in self?.play() }
      controller.onLater = { [weak self] in self?.later() }
    }

    /// Le compte à rebours et les libellés changent en place ; une autre
    /// proposition (autre épisode, autre heure) remplace celle de l'item.
    func apply(_ nextUp: OnyxAppleNativeNextUp?, item: AVPlayerItem?) {
      let same = Self.sameProposal(current, nextUp)
      current = nextUp
      controller.show(nextUp)
      fetchImageIfNeeded(nextUp?.imageUrl)
      guard !same else { return }
      answered = false
      if nextUp == nil, controller.playerViewController != nil {
        controller.dismissContentProposal(for: .defer, animated: true)
      }
      attach(to: item ?? self.item)
    }

    /// Le moteur remplace l'item à chaque rechargement : la proposition se
    /// repose sur le nouveau, et quitte l'ancien.
    func attach(to item: AVPlayerItem?) {
      if let old = self.item, old !== item { old.nextContentProposal = nil }
      self.item = item
      guard let item else { return }
      guard let current, !answered else {
        item.nextContentProposal = nil
        return
      }
      item.nextContentProposal = proposal(current, on: item)
    }

    func detach() {
      imageTask?.cancel()
      imageTask = nil
      item?.nextContentProposal = nil
      item = nil
    }

    func shouldPresent(_ proposal: AVContentProposal) -> Bool {
      current != nil && !answered
    }

    func accepted(_ proposal: AVContentProposal) {
      guard !answered else { return }
      answered = true
      onPlay()
    }

    func deferred(_ proposal: AVContentProposal) {
      guard !answered else { return }
      answered = true
      onLater()
    }

    private func play() {
      guard !answered else { return }
      answered = true
      controller.dismissContentProposal(for: .accept, animated: true)
      onPlay()
    }

    /// `.defer`, jamais `.reject` : d'après l'en-tête, un refus ferme le
    /// lecteur.
    private func later() {
      guard !answered else { return }
      answered = true
      controller.dismissContentProposal(for: .defer, animated: true)
      onLater()
    }

    /// Dart pose souvent la proposition au début du générique, donc à une
    /// heure déjà passée ou presque : elle est alors présentée dans une
    /// demi-seconde. AVKit présenterait-il une proposition en retard ? À
    /// confirmer à l'appareil ; ce report n'en dépend pas.
    private func proposal(_ nextUp: OnyxAppleNativeNextUp, on item: AVPlayerItem) -> AVContentProposal {
      var time = CMTime(value: nextUp.transitionMs, timescale: 1000)
      let now = item.currentTime()
      if now.isNumeric, now.seconds > 0 {
        let soon = CMTimeAdd(now, CMTime(value: 500, timescale: 1000))
        if CMTimeCompare(time, soon) < 0 { time = soon }
      }
      // `automaticAcceptanceInterval` vaut NaN par défaut : pas d'acceptation
      // automatique, Dart enchaîne lui-même.
      return AVContentProposal(
        contentTimeForTransition: time, title: nextUp.title,
        previewImage: image?.url == nextUp.imageUrl ? image?.image : nil)
    }

    private func fetchImageIfNeeded(_ value: String?) {
      if let image, image.url == value {
        controller.image = image.image
        return
      }
      controller.image = nil
      guard let value, imageRequested != value, let url = URL(string: value) else { return }
      imageTask?.cancel()
      imageRequested = value
      imageTask = Task { [weak self] in
        do {
          let (data, _) = try await URLSession.shared.data(from: url)
          guard let decoded = UIImage(data: data), let self, !Task.isCancelled else { return }
          self.image = (value, decoded)
          if self.current?.imageUrl == value { self.controller.image = decoded }
        } catch {
          // Sans image, la proposition garde son titre et ses boutons.
          NSLog("Onyx: image de l'épisode suivant indisponible : \(error.localizedDescription)")
        }
      }
    }

    private static func sameProposal(_ a: OnyxAppleNativeNextUp?, _ b: OnyxAppleNativeNextUp?) -> Bool {
      a?.title == b?.title && a?.subtitle == b?.subtitle && a?.imageUrl == b?.imageUrl
        && a?.transitionMs == b?.transitionMs
    }
  }

  /// La proposition à l'écran : l'image en cours réduite dans un coin, et en
  /// bas à gauche l'épisode suivant, le compte à rebours de Dart et deux
  /// boutons.
  final class NativeNextUpProposalController: AVContentProposalViewController {
    var onPlay: (() -> Void)?
    var onLater: (() -> Void)?

    var image: UIImage? {
      didSet { imageView.image = image }
    }

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let laterButton = UIButton(type: .system)
    private let countdown = NativeCountdownRing()
    private var nextUp: OnyxAppleNativeNextUp?
    /// Le plus long compte à rebours vu pour cet épisode : la pastille se vide
    /// de là jusqu'à zéro, comme celle d'Onyx.
    private var countdownTotal: Int64 = 0

    override var preferredPlayerViewFrame: CGRect {
      let bounds = view.window?.bounds ?? playerViewController?.view.bounds ?? view.bounds
      let width = (bounds.width * 0.42).rounded()
      return CGRect(x: bounds.maxX - width - 90, y: 90, width: width, height: (width * 9 / 16).rounded())
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [playButton] }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .black

      imageView.contentMode = .scaleAspectFill
      imageView.clipsToBounds = true
      imageView.layer.cornerRadius = 12
      imageView.backgroundColor = UIColor(white: 0.15, alpha: 1)
      titleLabel.font = .preferredFont(forTextStyle: .title2)
      titleLabel.textColor = .white
      titleLabel.numberOfLines = 2
      subtitleLabel.font = .preferredFont(forTextStyle: .callout)
      subtitleLabel.textColor = UIColor(white: 1, alpha: 0.7)
      subtitleLabel.numberOfLines = 3
      playButton.addAction(
        UIAction { [weak self] _ in MainActor.assumeIsolated { self?.onPlay?() } }, for: .primaryActionTriggered)
      laterButton.addAction(
        UIAction { [weak self] _ in MainActor.assumeIsolated { self?.onLater?() } }, for: .primaryActionTriggered)

      let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
      text.axis = .vertical
      text.spacing = 8
      let buttons = UIStackView(arrangedSubviews: [countdown, playButton, laterButton])
      buttons.axis = .horizontal
      buttons.spacing = 24
      buttons.alignment = .center
      let column = UIStackView(arrangedSubviews: [text, buttons])
      column.axis = .vertical
      column.spacing = 40
      column.alignment = .leading
      let row = UIStackView(arrangedSubviews: [imageView, column])
      row.axis = .horizontal
      row.spacing = 48
      row.alignment = .center
      row.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(row)
      NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 90),
        row.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -90),
        row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -110),
        imageView.widthAnchor.constraint(equalToConstant: 560),
        imageView.heightAnchor.constraint(equalToConstant: 315),
        countdown.widthAnchor.constraint(equalToConstant: 64),
        countdown.heightAnchor.constraint(equalToConstant: 64),
      ])
      render()
    }

    /// Mise à jour en place, sans nouvelle présentation : le focus reste sur
    /// le bouton où il est.
    func show(_ nextUp: OnyxAppleNativeNextUp?) {
      if nextUp?.title != self.nextUp?.title { countdownTotal = 0 }
      self.nextUp = nextUp
      if let seconds = nextUp?.countdownSeconds { countdownTotal = max(countdownTotal, seconds) }
      if isViewLoaded { render() }
    }

    private func render() {
      titleLabel.text = nextUp?.title
      subtitleLabel.text = nextUp?.subtitle
      subtitleLabel.isHidden = nextUp?.subtitle == nil
      playButton.setTitle(nextUp?.playLabel, for: .normal)
      laterButton.setTitle(nextUp?.laterLabel, for: .normal)
      // Le contrat ne porte pas de libellé traduit pour le compte à rebours :
      // un chiffre dans une pastille qui se vide se passe de langue.
      if let seconds = nextUp?.countdownSeconds, countdownTotal > 0 {
        countdown.isHidden = false
        countdown.show(seconds: seconds, fraction: Double(seconds) / Double(countdownTotal))
      } else {
        countdown.isHidden = true
      }
    }
  }

  /// Les secondes qui restent, dans un anneau qui se vide.
  final class NativeCountdownRing: UIView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let label = UILabel()

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      for (shape, alpha) in [(track, 0.25), (progress, 1.0)] {
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = UIColor(white: 1, alpha: alpha).cgColor
        shape.lineWidth = 5
        shape.lineCap = .round
        layer.addSublayer(shape)
      }
      label.font = .monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
      label.textColor = .white
      label.textAlignment = .center
      label.frame = bounds
      label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }

    override var intrinsicContentSize: CGSize { CGSize(width: 64, height: 64) }

    func show(seconds: Int64, fraction: Double) {
      label.text = String(seconds)
      progress.strokeEnd = CGFloat(min(max(fraction, 0), 1))
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      let radius = min(bounds.width, bounds.height) / 2 - 3
      let path = UIBezierPath(
        arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
        startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true
      ).cgPath
      for shape in [track, progress] {
        shape.frame = bounds
        shape.path = path
      }
    }
  }
#endif
