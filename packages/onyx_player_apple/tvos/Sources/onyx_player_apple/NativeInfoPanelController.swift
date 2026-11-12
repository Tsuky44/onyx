#if os(tvOS)
  import AVKit
  import UIKit

  /// Les onglets ajoutés au panneau d'infos d'AVKit (`customInfoViewControllers`) :
  /// Épisodes, Regarder ensemble, Stats.
  ///
  /// Un contrôleur par panneau, gardé d'une spec à l'autre : réaffecter la
  /// liste referait les onglets et ferait perdre le focus. Elle ne l'est que
  /// quand les onglets eux-mêmes changent.
  @MainActor
  final class NativeInfoPanels {
    private var controllers: [NativeInfoPanelController] = []
    private let statsValues: () -> [String: String]
    private let onGesture: (_ panelId: String, _ gesture: NativeInfoPanelController.Gesture) -> Void

    init(
      statsValues: @escaping () -> [String: String],
      onGesture: @escaping (_ panelId: String, _ gesture: NativeInfoPanelController.Gesture) -> Void
    ) {
      self.statsValues = statsValues
      self.onGesture = onGesture
    }

    func apply(_ panels: [OnyxAppleNativePanel], to player: AVPlayerViewController) {
      var seen = Set<String>()
      let panels = panels.filter { seen.insert($0.id).inserted }
      let sameTabs =
        controllers.map(\.panelId) == panels.map(\.id)
        && zip(controllers, panels).allSatisfy { $0.title == $1.title }
      if sameTabs {
        for (controller, panel) in zip(controllers, panels) { controller.update(panel) }
        return
      }
      let existing = Dictionary(uniqueKeysWithValues: controllers.map { ($0.panelId, $0) })
      controllers = panels.map { panel in
        if let controller = existing[panel.id] {
          controller.update(panel)
          return controller
        }
        return NativeInfoPanelController(panel: panel, statsValues: statsValues) { [weak self] gesture in
          self?.onGesture(panel.id, gesture)
        }
      }
      player.customInfoViewControllers = controllers
    }
  }

  /// Un panneau générique : des onglets (les saisons), des boutons, un
  /// paragraphe et des lignes focalisables. Mis à jour en place.
  final class NativeInfoPanelController: UIViewController, UICollectionViewDelegate {
    enum Gesture {
      case row(String)
      case tab(String)
      case action(String)
    }

    /// `NativeTvIds.statsPanel` : Swift remplit lui-même la valeur de chaque
    /// ligne, que Dart ne connaît pas.
    static let statsPanelId = "stats"

    let panelId: String
    private var panel: OnyxAppleNativePanel
    private let statsValues: () -> [String: String]
    private let onGesture: (Gesture) -> Void

    private let tabsStack = UIStackView()
    private let actionsStack = UIStackView()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    /// La ligne des onglets, en haut de la colonne des lignes.
    private let header = UIStackView()
    /// La colonne de présentation d'un panneau qui a un `headline`
    /// (Regarder ensemble) : une carte à gauche, avec la petite ligne, le
    /// grand texte, le paragraphe et les boutons. Les lignes passent à
    /// droite, sous leur titre. Sans elle, le panneau n'avait qu'un
    /// paragraphe et un bouton au bout de la ligne, sur toute la largeur de
    /// l'écran.
    private let lead = UIView()
    /// La carte de présentation puis la colonne des lignes, côte à côte.
    private let root = UIStackView()
    private let eyebrowLabel = UILabel()
    private let headlineLabel = UILabel()
    private let leadMessageLabel = UILabel()
    private let leadSpinner = UIActivityIndicatorView(style: .medium)
    private let leadActionsRow = UIStackView()
    private let rowsTitleLabel = UILabel()
    private var actionsInLead = false
    /// Toute la largeur du panneau, active quand aucune ligne ne prend le
    /// focus (Regarder ensemble, sans séance ou avec ses participants) : le
    /// seul bouton est alors à droite de l'en-tête, hors de la trajectoire
    /// du focus qui descend de l'onglet d'AVKit, et « Démarrer une séance »
    /// restait injoignable — l'appui ne faisait rien.
    private let actionsFocusGuide = UIFocusGuide()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout(cards: false))
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
    private var rows: [String: OnyxAppleNativePanelRow] = [:]
    /// La disposition posée sur la grille (cartes ou texte, et ses colonnes).
    private var layoutKey: String?
    private var liveStats: [String: String] = [:]
    private var statsTimer: Timer?
    /// Le focus entre une fois sur la ligne en cours, puis reste où
    /// l'utilisateur l'a laissé.
    private var scrolledToSelection = false

    init(
      panel: OnyxAppleNativePanel, statsValues: @escaping () -> [String: String],
      onGesture: @escaping (Gesture) -> Void
    ) {
      self.panelId = panel.id
      self.panel = panel
      self.statsValues = statsValues
      self.onGesture = onGesture
      super.init(nibName: nil, bundle: nil)
      title = panel.title
      // AVKit dimensionne l'onglet d'après cette taille (en-tête,
      // `customInfoViewControllers`).
      preferredContentSize = CGSize(width: 1740, height: 480)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }

    func update(_ panel: OnyxAppleNativePanel) {
      let old = self.panel
      self.panel = panel
      title = panel.title
      guard isViewLoaded else { return }
      render(old: old)
    }

    // MARK: - Vue

    override func viewDidLoad() {
      super.viewDidLoad()
      tabsStack.axis = .horizontal
      tabsStack.spacing = 16
      actionsStack.axis = .horizontal
      actionsStack.spacing = 16
      header.axis = .horizontal
      header.alignment = .center
      header.addArrangedSubview(tabsStack)
      header.addArrangedSubview(UIView())
      header.addArrangedSubview(actionsStack)
      messageLabel.font = .preferredFont(forTextStyle: .callout)
      messageLabel.textColor = UIColor(white: 1, alpha: 0.8)
      // Sans limite : l'erreur suit le texte d'accueil, et trois lignes la
      // coupaient, si bien qu'un échec ne se voyait pas.
      messageLabel.numberOfLines = 0
      rowsTitleLabel.font = .preferredFont(forTextStyle: .headline)
      rowsTitleLabel.textColor = .white

      eyebrowLabel.font = .preferredFont(forTextStyle: .caption1)
      eyebrowLabel.textColor = UIColor(white: 1, alpha: 0.6)
      headlineLabel.textColor = .white
      headlineLabel.numberOfLines = 2
      headlineLabel.adjustsFontSizeToFitWidth = true
      headlineLabel.minimumScaleFactor = 0.5
      leadMessageLabel.font = .preferredFont(forTextStyle: .body)
      leadMessageLabel.textColor = UIColor(white: 1, alpha: 0.75)
      leadMessageLabel.numberOfLines = 0
      leadSpinner.color = .white
      leadActionsRow.axis = .horizontal
      leadActionsRow.spacing = 20
      leadActionsRow.alignment = .center
      leadActionsRow.addArrangedSubview(leadSpinner)
      leadActionsRow.addArrangedSubview(UIView())
      let leadStack = UIStackView(arrangedSubviews: [
        eyebrowLabel, headlineLabel, leadMessageLabel, leadActionsRow,
      ])
      leadStack.axis = .vertical
      leadStack.spacing = 14
      leadStack.setCustomSpacing(6, after: eyebrowLabel)
      leadStack.setCustomSpacing(28, after: leadMessageLabel)
      leadStack.translatesAutoresizingMaskIntoConstraints = false
      lead.backgroundColor = UIColor(white: 1, alpha: 0.08)
      lead.layer.cornerRadius = 28
      lead.layer.cornerCurve = .continuous
      lead.addSubview(leadStack)

      collection.backgroundColor = .clear
      collection.delegate = self
      collection.remembersLastFocusedIndexPath = true
      collection.register(NativePanelCell.self, forCellWithReuseIdentifier: NativePanelCell.reuseId)
      dataSource = UICollectionViewDiffableDataSource(collectionView: collection) {
        [weak self] collection, indexPath, id in
        let cell = collection.dequeueReusableCell(withReuseIdentifier: NativePanelCell.reuseId, for: indexPath)
        if let self, let cell = cell as? NativePanelCell, let row = self.rows[id] {
          cell.show(row, detail: self.detail(of: row))
        }
        return cell
      }

      let rowsColumn = UIStackView(arrangedSubviews: [header, messageLabel, rowsTitleLabel, collection])
      rowsColumn.axis = .vertical
      rowsColumn.spacing = 20
      // La carte n'entre dans la pile que pour un panneau qui en a une
      // (`render`) : masquée, sa largeur fixe se battrait avec la pile.
      root.addArrangedSubview(rowsColumn)
      root.axis = .horizontal
      root.spacing = 48
      root.translatesAutoresizingMaskIntoConstraints = false
      spinner.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(root)
      view.addSubview(spinner)
      view.addLayoutGuide(actionsFocusGuide)
      NSLayoutConstraint.activate([
        actionsFocusGuide.topAnchor.constraint(equalTo: view.topAnchor),
        actionsFocusGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        actionsFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        actionsFocusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        root.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
        root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
        root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        lead.widthAnchor.constraint(equalToConstant: 720),
        leadStack.leadingAnchor.constraint(equalTo: lead.leadingAnchor, constant: 40),
        leadStack.trailingAnchor.constraint(equalTo: lead.trailingAnchor, constant: -40),
        leadStack.centerYAnchor.constraint(equalTo: lead.centerYAnchor),
        leadStack.topAnchor.constraint(greaterThanOrEqualTo: lead.topAnchor, constant: 32),
        leadStack.bottomAnchor.constraint(lessThanOrEqualTo: lead.bottomAnchor, constant: -32),
        // Au centre du panneau, pas de la grille : vide pendant l'attente,
        // elle est masquée et la pile la réduit à rien, roue comprise.
        spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
      render(old: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      guard panelId == Self.statsPanelId else { return }
      refreshStats()
      statsTimer?.invalidate()
      statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.refreshStats() }
      }
    }

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      statsTimer?.invalidate()
      statsTimer = nil
    }

    private func refreshStats() {
      liveStats = statsValues()
      guard let dataSource else { return }
      var snapshot = dataSource.snapshot()
      snapshot.reconfigureItems(snapshot.itemIdentifiers)
      dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Rendu

    private func render(old: OnyxAppleNativePanel?) {
      let hasLead = panel.headline != nil
      if old?.tabs.map({ [$0.id, $0.label] }) != panel.tabs.map({ [$0.id, $0.label] }) {
        rebuild(tabsStack, with: panel.tabs.map { ($0.id, $0.label) }) { [weak self] id in
          self?.onGesture(.tab(id))
        }
      }
      for (button, tab) in zip(tabsStack.arrangedSubviews.compactMap { $0 as? UIButton }, panel.tabs) {
        button.configuration = Self.buttonConfiguration(tab.label, prominent: tab.selected)
      }
      if old?.actions != panel.actions {
        rebuild(actionsStack, with: panel.actions.map { ($0.id, $0.label) }) { [weak self] id in
          self?.onGesture(.action(id))
        }
      }
      // Le bouton qui ouvre une séance est celui du panneau : plein. Celui
      // qui la quitte reste discret, à côté du code.
      let prominent = hasLead && panel.eyebrow == nil
      for (button, action) in zip(actionsStack.arrangedSubviews.compactMap { $0 as? UIButton }, panel.actions) {
        button.configuration = Self.buttonConfiguration(action.label, prominent: prominent, icon: action.icon)
        button.isEnabled = !panel.loading
      }
      placeActions(inLead: hasLead)

      if hasLead, lead.superview == nil {
        root.insertArrangedSubview(lead, at: 0)
      } else if !hasLead, lead.superview != nil {
        lead.removeFromSuperview()
      }
      eyebrowLabel.text = panel.eyebrow?.uppercased()
      eyebrowLabel.isHidden = panel.eyebrow == nil
      renderHeadline()
      leadMessageLabel.text = panel.message
      leadMessageLabel.isHidden = panel.message == nil
      messageLabel.text = hasLead ? nil : panel.message
      messageLabel.isHidden = hasLead || panel.message == nil
      rowsTitleLabel.text = panel.rowsTitle
      rowsTitleLabel.isHidden = panel.rowsTitle == nil
      header.isHidden = panel.tabs.isEmpty && (hasLead || panel.actions.isEmpty)
      // Dans la carte, la roue se pose à côté du bouton ; ailleurs, au
      // centre du panneau.
      if panel.loading && hasLead { leadSpinner.startAnimating() } else { leadSpinner.stopAnimating() }
      if panel.loading && !hasLead { spinner.startAnimating() } else { spinner.stopAnimating() }
      renderRows(old: old)
      let firstAction = actionsStack.arrangedSubviews.first
      let rowsTakeFocus = panel.rows.contains(where: \.selectable)
      actionsFocusGuide.preferredFocusEnvironments = firstAction.map { [$0] } ?? []
      actionsFocusGuide.isEnabled = firstAction != nil && !rowsTakeFocus
    }

    /// Un code de séance s'écrit en chasse fixe, très grand et aéré : on le
    /// dicte à voix haute. Un titre, en gras de titre.
    private func renderHeadline() {
      guard let headline = panel.headline else {
        headlineLabel.attributedText = nil
        return
      }
      if panel.eyebrow != nil {
        headlineLabel.font = .monospacedSystemFont(ofSize: 84, weight: .bold)
        headlineLabel.attributedText = NSAttributedString(string: headline, attributes: [.kern: 10])
      } else {
        headlineLabel.font = .systemFont(ofSize: 52, weight: .bold)
        headlineLabel.attributedText = NSAttributedString(string: headline)
      }
    }

    /// Les boutons vont dans la carte de présentation quand il y en a une,
    /// sinon au bout de la ligne des onglets.
    private func placeActions(inLead: Bool) {
      guard inLead != actionsInLead || actionsStack.superview == nil else { return }
      actionsInLead = inLead
      actionsStack.removeFromSuperview()
      if inLead {
        leadActionsRow.insertArrangedSubview(actionsStack, at: 0)
      } else {
        header.addArrangedSubview(actionsStack)
      }
    }

    /// Où le focus entre dans le panneau : la ligne en cours s'il y en a,
    /// sinon le premier bouton.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
      if actionsFocusGuide.isEnabled, let first = actionsStack.arrangedSubviews.first {
        return [first]
      }
      return super.preferredFocusEnvironments
    }

    private func rebuild(_ stack: UIStackView, with items: [(String, String)], onTap: @escaping (String) -> Void) {
      for view in stack.arrangedSubviews { view.removeFromSuperview() }
      for (id, label) in items {
        let button = UIButton(
          configuration: Self.buttonConfiguration(label, prominent: false),
          primaryAction: UIAction { _ in MainActor.assumeIsolated { onTap(id) } })
        stack.addArrangedSubview(button)
      }
    }

    private static func buttonConfiguration(_ label: String, prominent: Bool, icon: String? = nil)
      -> UIButton.Configuration
    {
      var configuration: UIButton.Configuration = prominent ? .borderedProminent() : .bordered()
      configuration.title = label
      if let icon {
        configuration.image = UIImage(systemName: icon)
        configuration.imagePadding = 12
      }
      return configuration
    }

    /// Des cartes qui défilent de côté quand les lignes ont une image (les
    /// épisodes), une grille de texte sinon (participants, mesures).
    private func renderRows(old: OnyxAppleNativePanel?) {
      guard let dataSource else { return }
      let previous = rows
      var seen = Set<String>()
      let ordered = panel.rows.filter { seen.insert($0.id).inserted }
      rows = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })

      let cards = ordered.contains { $0.imageUrl != nil }
      // À côté de la carte de présentation, la colonne est plus étroite :
      // trois étapes se lisent l'une sous l'autre, des participants sur
      // deux colonnes. Ailleurs, trois colonnes (les statistiques).
      let hasLead = panel.headline != nil
      let columns = hasLead ? (ordered.count <= 3 ? 1 : 2) : 3
      let rowHeight: CGFloat = hasLead ? 116 : 96
      let key = "\(cards)-\(columns)-\(rowHeight)"
      if layoutKey != key {
        layoutKey = key
        collection.setCollectionViewLayout(
          layout(cards: cards, columns: columns, rowHeight: rowHeight), animated: false)
      }
      var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
      snapshot.appendSections([0])
      snapshot.appendItems(ordered.map(\.id))
      snapshot.reconfigureItems(ordered.filter { previous[$0.id] != nil && previous[$0.id] != $0 }.map(\.id))
      dataSource.apply(snapshot, animatingDifferences: false)
      collection.isHidden = panel.loading && ordered.isEmpty

      if !scrolledToSelection, let index = ordered.firstIndex(where: \.selected) {
        scrolledToSelection = true
        collection.layoutIfNeeded()
        collection.scrollToItem(
          at: IndexPath(item: index, section: 0), at: cards ? .centeredHorizontally : .centeredVertically,
          animated: false)
      }
    }

    private func layout(cards: Bool, columns: Int = 3, rowHeight: CGFloat = 96)
      -> UICollectionViewCompositionalLayout
    {
      if cards {
        let item = NSCollectionLayoutItem(
          layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(
          layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(400), heightDimension: .absolute(330)),
          subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 40
        section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
        return UICollectionViewCompositionalLayout(section: section)
      }
      let item = NSCollectionLayoutItem(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .fractionalHeight(1)))
      item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
      let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(rowHeight)),
        subitems: Array(repeating: item, count: columns))
      return UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))
    }

    private func detail(of row: OnyxAppleNativePanelRow) -> String? {
      guard panelId == Self.statsPanelId else { return row.detail }
      return liveStats[row.id] ?? "—"
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
      row(at: indexPath)?.selectable ?? false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
      guard let row = row(at: indexPath), row.selectable else { return }
      onGesture(.row(row.id))
    }

    /// L'épisode qui joue : le focus y entre.
    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
      guard let id = dataSource?.snapshot().itemIdentifiers.first(where: { rows[$0]?.selected == true })
      else { return nil }
      return dataSource?.indexPath(for: id)
    }

    private func row(at indexPath: IndexPath) -> OnyxAppleNativePanelRow? {
      dataSource?.itemIdentifier(for: indexPath).flatMap { rows[$0] }
    }
  }

  /// Une ligne : une carte d'épisode (image, avancement) ou une case de texte.
  final class NativePanelCell: UICollectionViewCell {
    static let reuseId = "NativePanelCell"
    private static let images = NSCache<NSString, UIImage>()

    private let imageView = UIImageView()
    /// L'initiale d'un participant, le numéro d'une étape.
    private let badgeLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let marker = UIImageView(image: UIImage(systemName: "play.fill"))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private var imageUrl: String?
    private var imageTask: Task<Void, Never>?

    override init(frame: CGRect) {
      super.init(frame: frame)
      contentView.layer.cornerRadius = 12
      contentView.backgroundColor = UIColor(white: 1, alpha: 0.08)
      imageView.contentMode = .scaleAspectFill
      imageView.clipsToBounds = true
      imageView.layer.cornerRadius = 12
      imageView.backgroundColor = UIColor(white: 0.15, alpha: 1)
      marker.tintColor = .white
      marker.setContentHuggingPriority(.required, for: .horizontal)
      titleLabel.font = .preferredFont(forTextStyle: .headline)
      titleLabel.textColor = .white
      subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
      subtitleLabel.textColor = UIColor(white: 1, alpha: 0.7)
      detailLabel.font = .preferredFont(forTextStyle: .callout)
      detailLabel.textColor = UIColor(white: 1, alpha: 0.85)
      detailLabel.textAlignment = .right
      detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

      let titleRow = UIStackView(arrangedSubviews: [marker, titleLabel, detailLabel])
      titleRow.spacing = 10
      titleRow.alignment = .center
      badgeLabel.font = .systemFont(ofSize: 30, weight: .bold)
      badgeLabel.textColor = .white
      badgeLabel.textAlignment = .center
      badgeLabel.backgroundColor = UIColor(white: 1, alpha: 0.16)
      badgeLabel.layer.cornerRadius = 30
      badgeLabel.layer.masksToBounds = true
      badgeLabel.isHidden = true

      let column = UIStackView(arrangedSubviews: [imageView, progress, titleRow, subtitleLabel])
      column.axis = .vertical
      column.spacing = 8
      let content = UIStackView(arrangedSubviews: [badgeLabel, column])
      content.axis = .horizontal
      content.spacing = 18
      content.alignment = .center
      content.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(content)
      // Souple : une ligne de texte masque l'image, que la pile réduit à
      // rien, et un rapport obligatoire s'y opposerait.
      let ratio = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 9.0 / 16)
      ratio.priority = UILayoutPriority(999)
      NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
        content.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
        content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
        content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        badgeLabel.widthAnchor.constraint(equalToConstant: 60),
        badgeLabel.heightAnchor.constraint(equalToConstant: 60),
        ratio,
      ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }

    func show(_ row: OnyxAppleNativePanelRow, detail: String?) {
      titleLabel.text = row.title
      subtitleLabel.text = row.subtitle
      subtitleLabel.isHidden = row.subtitle == nil
      detailLabel.text = detail
      detailLabel.isHidden = detail == nil
      badgeLabel.text = row.badge
      badgeLabel.isHidden = row.badge == nil
      marker.isHidden = !row.selected
      progress.isHidden = row.progress == nil
      progress.progress = Float(row.progress ?? 0)
      imageView.isHidden = row.imageUrl == nil
      load(row.imageUrl)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
      super.didUpdateFocus(in: context, with: coordinator)
      let focused = isFocused
      coordinator.addCoordinatedAnimations {
        self.transform = focused ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
        self.contentView.backgroundColor = UIColor(white: 1, alpha: focused ? 0.25 : 0.08)
      }
    }

    private func load(_ value: String?) {
      guard value != imageUrl else { return }
      imageTask?.cancel()
      imageUrl = value
      imageView.image = value.flatMap { Self.images.object(forKey: $0 as NSString) }
      guard let value, imageView.image == nil, let url = URL(string: value) else { return }
      imageTask = Task { [weak self] in
        do {
          let (data, _) = try await URLSession.shared.data(from: url)
          guard let image = UIImage(data: data), !Task.isCancelled else { return }
          Self.images.setObject(image, forKey: value as NSString)
          guard let self, self.imageUrl == value else { return }
          self.imageView.image = image
        } catch {
          // Une vignette qui manque laisse la carte grise : le titre suffit.
          NSLog("Onyx: vignette du panneau natif indisponible : \(error.localizedDescription)")
        }
      }
    }
  }

  /// Les valeurs du panneau Stats, mises en forme ici : Dart ne fournit que
  /// les libellés (§3.2 de l'inventaire). Les unités (`fps`, `Mb/s`) se
  /// lisent dans toutes les langues de l'app.
  enum NativeStatsFormat {
    static func values(_ stats: OnyxApplePlaybackStats, videoFormat: String) -> [String: String] {
      var values: [String: String] = [:]
      values["route"] = stats.route
      values["videoCodec"] = stats.videoCodec
      values["videoDecoder"] = stats.videoDecoder
      values["audioDecoder"] = stats.audioDecoder
      values["audioDelivery"] = stats.audioDelivery
      values["container"] = stats.container
      values["observedFps"] = stats.observedFps.map { "\(number($0, digits: 2)) fps" }
      values["containerFps"] = stats.containerFps.map { "\(number($0, digits: 3)) fps" }
      values["droppedFrames"] = stats.droppedFrames.map { number(Double($0), digits: 0) }
      values["averageBitrateMbps"] = stats.averageBitrateMbps.map { "\(number($0, digits: 1)) Mb/s" }
      values["videoBitrate"] = stats.videoBitrate.map { "\(number(Double($0) / 1_000_000, digits: 1)) Mb/s" }
      values["videoFormat"] = Self.videoFormats[videoFormat] ?? videoFormat
      return values
    }

    private static let videoFormats = [
      "sdr": "SDR", "hdr10": "HDR10", "hdr10plus": "HDR10+", "dolbyvision": "Dolby Vision", "hlg": "HLG",
    ]

    private static func number(_ value: Double, digits: Int) -> String {
      guard value.isFinite else { return "—" }
      return value.formatted(.number.precision(.fractionLength(0...digits)))
    }
  }
#endif
