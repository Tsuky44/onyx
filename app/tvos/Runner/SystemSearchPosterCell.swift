import CoreText
import UIKit

/// Une affiche de la recherche du système (ADR-0129), au dessin des cartes de
/// l'app (`PosterCard`) : l'image aux coins arrondis, qui se soulève de 10 %
/// depuis son pied sous le focus, son ombre pour seul signe (ADR-0118), le
/// titre et l'année dessous.
///
/// Un titre que le serveur n'a pas porte le signe que l'app lui donne
/// partout : l'affiche voilée (`AppColors.unavailableTint`) et la pastille de
/// verre « Indispo » en haut à droite (`UnavailableBadge`).
final class SystemSearchPosterCell: UICollectionViewCell {
  static let reuseIdentifier = "poster"

  private static let captionGap: CGFloat = 14
  private static let titleHeight: CGFloat = 30
  private static let subtitleHeight: CGFloat = 26

  /// La hauteur d'une case de [width] de large : l'affiche en 2:3, puis ses
  /// deux lignes.
  static func height(forWidth width: CGFloat) -> CGFloat {
    (width * 1.5).rounded() + captionGap + titleHeight + 2 + subtitleHeight
  }

  /// Porte l'ombre et le soulèvement ; [poster], dedans, découpe les coins.
  private let lift = UIView()
  private let poster = UIView()
  private let imageView = UIImageView()
  private let veil = UIView()
  private let badge = SystemSearchBadge()
  private let watchedMark = SystemSearchWatchedMark()
  private let progressTrack = UIView()
  private let progressFill = UIView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()

  private var item: SystemSearchItem?
  private var palette: SystemSearchPalette?
  private var loading: URLSessionDataTask?
  private var shownURL: URL?

  override init(frame: CGRect) {
    super.init(frame: frame)

    lift.layer.shadowColor = UIColor.black.cgColor
    lift.layer.shadowOpacity = 0
    lift.layer.shadowRadius = 28
    lift.layer.shadowOffset = CGSize(width: 0, height: 26)
    contentView.addSubview(lift)

    poster.layer.cornerRadius = SystemSearchMetrics.posterRadius
    poster.layer.cornerCurve = .continuous
    poster.layer.masksToBounds = true
    lift.addSubview(poster)

    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    poster.addSubview(imageView)

    veil.isHidden = true
    poster.addSubview(veil)

    progressTrack.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    progressTrack.layer.masksToBounds = true
    progressTrack.isHidden = true
    progressTrack.addSubview(progressFill)
    poster.addSubview(progressTrack)

    badge.isHidden = true
    poster.addSubview(badge)
    watchedMark.isHidden = true
    poster.addSubview(watchedMark)

    titleLabel.font = SystemSearchFont.font(.semibold, size: 23)
    titleLabel.lineBreakMode = .byTruncatingTail
    contentView.addSubview(titleLabel)

    subtitleLabel.font = SystemSearchFont.font(.regular, size: 19)
    subtitleLabel.lineBreakMode = .byTruncatingTail
    contentView.addSubview(subtitleLabel)

    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SystemSearchPosterCell ne se charge pas d'un storyboard")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let width = contentView.bounds.width
    let posterHeight = (width * 1.5).rounded()
    let inset = SystemSearchMetrics.overlayInset

    // Par le centre et les bornes : `frame` n'a pas de sens sur une vue
    // transformée, et l'affiche focalisée l'est.
    lift.bounds = CGRect(x: 0, y: 0, width: width, height: posterHeight)
    lift.center = CGPoint(x: width / 2, y: posterHeight / 2)
    lift.layer.shadowPath =
      UIBezierPath(
        roundedRect: lift.bounds, cornerRadius: SystemSearchMetrics.posterRadius
      ).cgPath
    poster.frame = lift.bounds
    imageView.frame = poster.bounds
    veil.frame = poster.bounds

    let badgeSize = badge.sizeThatFits(poster.bounds.size)
    badge.frame = CGRect(
      x: width - inset - badgeSize.width, y: inset,
      width: badgeSize.width, height: badgeSize.height)
    let mark = SystemSearchWatchedMark.side
    watchedMark.frame = CGRect(x: width - inset - mark, y: inset, width: mark, height: mark)

    let trackHeight: CGFloat = 6
    progressTrack.frame = CGRect(
      x: inset, y: posterHeight - inset - trackHeight,
      width: width - inset * 2, height: trackHeight)
    progressTrack.layer.cornerRadius = trackHeight / 2
    let progress = CGFloat(min(max(item?.progress ?? 0, 0), 1))
    progressFill.frame = CGRect(
      x: 0, y: 0, width: progressTrack.bounds.width * progress, height: trackHeight)

    let titleTop = posterHeight + SystemSearchPosterCell.captionGap
    titleLabel.frame = CGRect(
      x: 0, y: titleTop, width: width, height: SystemSearchPosterCell.titleHeight)
    subtitleLabel.frame = CGRect(
      x: 0, y: titleTop + SystemSearchPosterCell.titleHeight + 2,
      width: width, height: SystemSearchPosterCell.subtitleHeight)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    loading?.cancel()
    loading = nil
    shownURL = nil
    imageView.image = nil
    item = nil
    applyFocus(false)
  }

  /// Dessine [item]. Sans effet si la case le montre déjà : la grille le
  /// redonne à chaque mise à jour.
  func show(_ item: SystemSearchItem, palette: SystemSearchPalette) {
    guard item != self.item else { return }
    self.item = item
    self.palette = palette

    poster.backgroundColor = palette.surfaceElevated
    veil.backgroundColor = palette.unavailableTint
    veil.isHidden = !item.dimmed
    badge.show(item.badge, tint: item.badgeTint)
    // Une seule marque dans le coin : la pastille d'un titre absent prime.
    watchedMark.tintColor = palette.success
    watchedMark.isHidden = !item.watched || item.badge != nil
    progressTrack.isHidden = item.progress == nil
    progressFill.backgroundColor = palette.progress
    titleLabel.text = item.title
    subtitleLabel.text = item.subtitle
    subtitleLabel.textColor = palette.textMuted
    accessibilityLabel = [item.title, item.subtitle, item.badge ?? ""]
      .filter { !$0.isEmpty }
      .joined(separator: ", ")

    applyFocus(isFocused)
    load(item.poster)
    setNeedsLayout()
  }

  private func load(_ url: URL?) {
    guard url != shownURL else { return }
    loading?.cancel()
    loading = nil
    shownURL = url
    imageView.image = nil
    guard let url = url else { return }

    // Une image déjà en mémoire arrive avant le retour de `load` : elle se
    // pose sans fondu, les autres apparaissent en douceur.
    var immediate = true
    loading = SystemSearchImages.shared.load(url) { [weak self] image in
      guard let self = self, self.shownURL == url, let image = image else { return }
      self.imageView.image = image
      guard !immediate else { return }
      self.imageView.alpha = 0
      UIView.animate(withDuration: 0.18) {
        self.imageView.alpha = 1
      }
    }
    immediate = false
  }

  // MARK: - Focus

  override func didUpdateFocus(
    in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator
  ) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = isFocused
    coordinator.addCoordinatedAnimations(
      {
        self.applyFocus(focused)
      }, completion: nil)
  }

  private func applyFocus(_ focused: Bool) {
    // L'affiche grandit depuis son pied : le titre dessous ne bouge pas, et
    // la place qu'elle prend est au-dessus, réservée par la grille.
    let scale = SystemSearchMetrics.lift
    let rise = lift.bounds.height * (scale - 1) / 2
    lift.transform =
      focused
      ? CGAffineTransform(translationX: 0, y: -rise).scaledBy(x: scale, y: scale)
      : .identity
    lift.layer.shadowOpacity = focused ? 0.7 : 0
    // Au-dessus de ses voisines, que son ombre recouvre.
    layer.zPosition = focused ? 1 : 0

    guard let palette = palette else { return }
    if focused {
      titleLabel.textColor = palette.textPrimary
    } else {
      titleLabel.textColor = item?.dimmed == true ? palette.textMuted : palette.textSecondary
    }
  }
}

/// La pastille de verre d'un titre absent, comme `UnavailableBadge` : fond
/// noir à 45 %, filet blanc, texte en petites lettres.
final class SystemSearchBadge: UIView {
  private let label = UILabel()
  private static let padding = CGSize(width: 12, height: 5)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor.black.withAlphaComponent(0.45)
    layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
    layer.borderWidth = 1
    layer.masksToBounds = true
    label.font = SystemSearchFont.font(.semibold, size: 16)
    label.textAlignment = .center
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SystemSearchBadge ne se charge pas d'un storyboard")
  }

  func show(_ text: String?, tint: UIColor?) {
    label.text = text
    label.textColor = tint ?? UIColor.white.withAlphaComponent(0.85)
    isHidden = (text ?? "").isEmpty
    setNeedsLayout()
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    let text = label.sizeThatFits(size)
    return CGSize(
      width: text.width.rounded(.up) + SystemSearchBadge.padding.width * 2,
      height: text.height.rounded(.up) + SystemSearchBadge.padding.height * 2)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    label.frame = bounds
    layer.cornerRadius = bounds.height / 2
  }
}

/// La coche d'un titre déjà vu, comme `WatchBadge` : un disque de verre
/// sombre, la couleur réduite au glyphe.
final class SystemSearchWatchedMark: UIView {
  static let side: CGFloat = 36

  private let glyph = UIImageView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor(white: 0.1, alpha: 0.95)
    layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
    layer.borderWidth = 1
    layer.cornerRadius = SystemSearchWatchedMark.side / 2
    glyph.image = UIImage(
      systemName: "checkmark",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
    glyph.contentMode = .center
    addSubview(glyph)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SystemSearchWatchedMark ne se charge pas d'un storyboard")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    glyph.frame = bounds
  }
}

/// Le titre d'un rayon : « Films · 4 ».
final class SystemSearchHeaderView: UICollectionReusableView {
  static let reuseIdentifier = "header"

  private let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    label.font = SystemSearchFont.font(.bold, size: 36)
    label.lineBreakMode = .byTruncatingTail
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SystemSearchHeaderView ne se charge pas d'un storyboard")
  }

  func show(_ title: String, palette: SystemSearchPalette) {
    label.text = title
    label.textColor = palette.textPrimary
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Calé en haut : le bas de la case est la place de l'affiche soulevée.
    label.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 46)
  }
}

/// Ce que l'écran dit quand il n'a aucune affiche à montrer.
final class SystemSearchEmptyView: UIView {
  private let titleLabel = UILabel()
  private let messageLabel = UILabel()

  init(palette: SystemSearchPalette) {
    super.init(frame: .zero)
    titleLabel.font = SystemSearchFont.font(.bold, size: 36)
    titleLabel.textColor = palette.textPrimary
    titleLabel.textAlignment = .center
    addSubview(titleLabel)
    messageLabel.font = SystemSearchFont.font(.regular, size: 25)
    messageLabel.textColor = palette.textSecondary
    messageLabel.textAlignment = .center
    messageLabel.numberOfLines = 2
    addSubview(messageLabel)
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SystemSearchEmptyView ne se charge pas d'un storyboard")
  }

  func show(title: String?, message: String?) {
    titleLabel.text = title
    messageLabel.text = message
    isHidden = (title ?? "").isEmpty && (message ?? "").isEmpty
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Sous le clavier, qui occupe le haut de l'écran : aux deux tiers.
    let width = min(bounds.width, 1000)
    let left = (bounds.width - width) / 2
    let top = bounds.height * 0.62
    titleLabel.frame = CGRect(x: left, y: top, width: width, height: 48)
    messageLabel.frame = CGRect(x: left, y: top + 60, width: width, height: 72)
  }
}

/// Les affiches, chargées une fois et gardées en mémoire tant que l'écran
/// vit ; le cache de `URLSession` les garde sur disque d'une fois sur l'autre.
final class SystemSearchImages {
  static let shared = SystemSearchImages()

  private let session: URLSession
  private let memory = NSCache<NSURL, UIImage>()

  private init() {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(
      memoryCapacity: 8 * 1024 * 1024, diskCapacity: 96 * 1024 * 1024, diskPath: "onyx-search")
    session = URLSession(configuration: configuration)
    memory.countLimit = 240
  }

  /// Rend l'image de [url] sur le fil principal, nil si elle n'a pas pu être
  /// lue. Tout de suite, sans requête, quand elle est déjà en mémoire.
  func load(_ url: URL, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
    if let cached = memory.object(forKey: url as NSURL) {
      completion(cached)
      return nil
    }
    let task = session.dataTask(with: url) { [weak self] data, _, _ in
      // Décodée ici, hors du fil principal : sinon c'est le défilement de la
      // grille qui paie le décodage de chaque affiche.
      let image = data.flatMap { UIImage(data: $0) }.map { $0.preparingForDisplay() ?? $0 }
      if let image = image {
        self?.memory.setObject(image, forKey: url as NSURL)
      }
      DispatchQueue.main.async {
        completion(image)
      }
    }
    task.resume()
    return task
  }
}

/// Manrope, la police de l'app, lue dans les ressources de Flutter. Si elle
/// n'y est pas, la police du système prend sa place.
enum SystemSearchFont {
  private static let registered: Bool = {
    let roots = [
      "flutter_assets/assets/fonts",
      "Frameworks/App.framework/flutter_assets/assets/fonts",
    ]
    for weight in ["400", "600", "700"] {
      for root in roots {
        let url = Bundle.main.bundleURL
          .appendingPathComponent(root)
          .appendingPathComponent("Manrope-\(weight).ttf")
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        break
      }
    }
    return true
  }()

  static func font(_ weight: UIFont.Weight, size: CGFloat) -> UIFont {
    _ = registered
    let name: String
    switch weight {
    case .bold: name = "Manrope-Bold"
    case .semibold: name = "Manrope-SemiBold"
    default: name = "Manrope-Regular"
    }
    return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
  }
}
