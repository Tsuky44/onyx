#if os(tvOS)
  import AVKit
  import UIKit

  /// Ce qu'Onyx pose sur l'image de l'écran natif, dans le
  /// `contentOverlayView`, donc sous la barre de transport d'AVKit :
  ///
  /// - l'annonce de Regarder ensemble (« alex a mis en pause », l'attente
  ///   d'un participant), en haut au centre ;
  /// - le logo du titre, en haut à gauche, tant que la barre de transport
  ///   est à l'écran : celui de la série pour un épisode, comme dans
  ///   l'interface Onyx.
  ///
  /// Posée après la couche des sous-titres image (`NativeBitmapSubtitles`,
  /// ADR-0107), elle passe au-dessus d'eux. Rien n'y est focalisable : elle
  /// ne prend jamais la télécommande.
  final class NativeOverlayView: UIView {
    private static let fade: TimeInterval = 0.25
    private static let logoHeight: CGFloat = 96
    private static let logoMaxWidth: CGFloat = 520

    /// Le texte déjà traduit par Dart, ou nil pour retirer l'annonce.
    var toast: String? {
      didSet { if oldValue != toast { render() } }
    }

    /// Le logo du titre, en URL absolue, ou nil pour n'en montrer aucun.
    var logoUrl: String? {
      didSet { if oldValue != logoUrl { loadLogo() } }
    }

    /// La barre de transport d'AVKit est à l'écran : le logo l'accompagne.
    /// À poser dans les animations coordonnées d'AVKit, pour qu'il apparaisse
    /// et s'efface avec elle.
    var chromeVisible = false {
      didSet { logoView.alpha = chromeVisible ? 1 : 0 }
    }

    private let pill = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let label = UILabel()
    private let logoView = UIImageView()
    private var logoWidth: NSLayoutConstraint?
    private var logoTask: Task<Void, Never>?

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      backgroundColor = .clear

      pill.clipsToBounds = true
      pill.layer.cornerRadius = 24
      pill.alpha = 0
      pill.translatesAutoresizingMaskIntoConstraints = false
      label.font = .preferredFont(forTextStyle: .headline)
      label.textColor = .white
      label.textAlignment = .center
      label.numberOfLines = 2
      label.translatesAutoresizingMaskIntoConstraints = false
      pill.contentView.addSubview(label)
      addSubview(pill)

      logoView.contentMode = .scaleAspectFit
      logoView.alpha = 0
      // Un logo clair sur une image claire : une ombre le détache.
      logoView.layer.shadowColor = UIColor.black.cgColor
      logoView.layer.shadowOpacity = 0.6
      logoView.layer.shadowRadius = 12
      logoView.layer.shadowOffset = .zero
      logoView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(logoView)
      // La largeur suit celle de l'image une fois chargée : centrée dans une
      // boîte plus large, elle ne serait plus calée à gauche.
      let logoWidth = logoView.widthAnchor.constraint(equalToConstant: 0)
      self.logoWidth = logoWidth
      NSLayoutConstraint.activate([
        logoView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        logoView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
        logoView.heightAnchor.constraint(equalToConstant: Self.logoHeight),
        logoWidth,
        pill.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 40),
        pill.centerXAnchor.constraint(equalTo: centerXAnchor),
        pill.widthAnchor.constraint(lessThanOrEqualToConstant: 1200),
        label.topAnchor.constraint(equalTo: pill.contentView.topAnchor, constant: 14),
        label.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor, constant: -14),
        label.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: 32),
        label.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -32),
      ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }

    func attach(to controller: AVPlayerViewController) {
      controller.loadViewIfNeeded()
      guard let overlay = controller.contentOverlayView else {
        // Sans couche, l'annonce manque, la séance tourne quand même.
        NSLog("Onyx: pas de contentOverlayView, annonces de Regarder ensemble masquées")
        return
      }
      frame = overlay.bounds
      autoresizingMask = [.flexibleWidth, .flexibleHeight]
      overlay.addSubview(self)
    }

    private func loadLogo() {
      logoTask?.cancel()
      logoView.image = nil
      logoWidth?.constant = 0
      guard let value = logoUrl, let url = URL(string: value) else { return }
      logoTask = Task { [weak self] in
        do {
          let (data, _) = try await URLSession.shared.data(from: url)
          // Décodé hors du fil principal : un logo de 500 px s'y décodait au
          // moment où la barre de transport apparaît.
          let image = await UIImage(data: data)?.byPreparingForDisplay()
          guard let self, let image, !Task.isCancelled, self.logoUrl == value else { return }
          self.logoView.image = image
          let ratio = image.size.width / max(image.size.height, 1)
          self.logoWidth?.constant = min(Self.logoMaxWidth, Self.logoHeight * ratio)
        } catch {
          // Sans logo, AVKit garde le titre dans sa barre : rien ne manque.
          NSLog("Onyx: logo du lecteur natif indisponible : \(error.localizedDescription)")
        }
      }
    }

    private func render() {
      if let toast {
        label.text = toast
        UIView.animate(withDuration: Self.fade) { self.pill.alpha = 1 }
      } else {
        // Le texte reste pendant le fondu : il ne disparaît qu'avec la
        // pastille.
        UIView.animate(withDuration: Self.fade) { self.pill.alpha = 0 }
      }
    }
  }
#endif
