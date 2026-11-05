#if os(tvOS)
  import AVKit
  import UIKit

  /// L'annonce de Regarder ensemble sur l'écran natif (« alex a mis en
  /// pause », l'attente d'un participant) : en haut au centre de l'image,
  /// dans le `contentOverlayView`, donc sous la barre de transport d'AVKit.
  ///
  /// Posée après la couche des sous-titres image (`NativeBitmapSubtitles`,
  /// ADR-0107), elle passe au-dessus d'eux. Rien n'y est focalisable : elle
  /// ne prend jamais la télécommande.
  final class NativeOverlayView: UIView {
    private static let fade: TimeInterval = 0.25

    /// Le texte déjà traduit par Dart, ou nil pour retirer l'annonce.
    var toast: String? {
      didSet { if oldValue != toast { render() } }
    }

    private let pill = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let label = UILabel()

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
      NSLayoutConstraint.activate([
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
