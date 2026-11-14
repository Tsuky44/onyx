import UIKit

/// L'écran de recherche du système (ADR-0129) : le champ et le clavier en
/// ligne de tvOS en tête, les affiches dessous, comme la recherche de
/// YouTube ou de l'app TV.
///
/// Tout ce qui se tape passe par `UISearchController` : la télécommande, la
/// dictée (bouton micro maintenu) et le clavier qu'un iPhone propose dès que
/// le champ est actif. C'est le moteur de focus d'UIKit qui descend du
/// clavier aux affiches et remonte.
final class SystemSearchScreen: UIViewController, UISearchResultsUpdating,
  UISearchControllerDelegate
{
  /// Le texte du champ a changé.
  var onQuery: ((String) -> Void)?

  /// L'affiche d'identifiant donné a été choisie.
  var onSelect: ((String) -> Void)?

  /// Retour (Menu) sur la télécommande.
  var onMenu: (() -> Void)?

  /// UIKit a retiré l'écran sans que l'app le demande.
  var onDismissedBySystem: (() -> Void)?

  /// Vrai quand c'est l'app qui retire l'écran : sa disparition n'est alors
  /// pas à annoncer.
  var dismissedByHost = false

  /// Vrai au retour d'une fiche, le temps que l'écran se pose : le focus
  /// revient sur l'affiche quittée, et non sur le clavier comme à l'ouverture.
  var returnsToResults = false
  private var returns = 0

  /// Le temps laissé au contrôleur de recherche pour finir de se présenter
  /// au retour d'une fiche : passé ce délai, le focus est à la télécommande.
  private static let returnPatience: TimeInterval = 1

  private let palette: SystemSearchPalette
  private let results: SystemSearchResultsController
  private let searchController: UISearchController
  private let container: UISearchContainerViewController
  private var lastQuery = ""

  init(palette: SystemSearchPalette, placeholder: String) {
    self.palette = palette
    results = SystemSearchResultsController(palette: palette)
    searchController = UISearchController(searchResultsController: results)
    container = UISearchContainerViewController(searchController: searchController)
    super.init(nibName: nil, bundle: nil)

    searchController.searchResultsUpdater = self
    searchController.delegate = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = placeholder
    // Le clavier suit la grille : il sort par le haut quand on descend dans
    // les affiches, et revient quand on remonte. Deux façons de le dire, selon
    // la version de tvOS : la propriété du contrôleur de recherche, dépréciée
    // par le SDK 27 au profit de la vue défilante déclarée par l'écran des
    // résultats. L'une est sans effet là où l'autre est lue.
    results.setContentScrollView(results.collectionView, for: .all)
    searchController.searchControllerObservedScrollView = results.collectionView
    results.onSelect = { [weak self] id in
      self?.onSelect?(id)
    }

    // Par-dessus Flutter, sans retirer sa vue : en plein écran, UIKit la sort
    // de la hiérarchie et le moteur Flutter cesse de dessiner (ADR-0105). Or
    // la fiche qu'on ouvre depuis une affiche se construit dessous.
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
    // L'app n'a qu'un thème, sombre : le clavier du système le suit.
    overrideUserInterfaceStyle = .dark
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SystemSearchScreen ne se charge pas d'un storyboard")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = palette.background

    addChild(container)
    container.view.frame = view.bounds
    container.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(container.view)
    container.didMove(toParent: self)

    // Retour est décidé ici et nulle part ailleurs : sans ce geste, UIKit
    // retire de lui-même un écran présenté, et Dart l'apprendrait après coup.
    let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
    menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
    view.addGestureRecognizer(menu)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard returnsToResults else { return }
    focusResults()
    // Le conteneur présente le contrôleur de recherche de son côté, parfois
    // après cet écran : `didPresentSearchController` redemande alors le focus.
    // Passé ce délai, on n'y touche plus.
    returns += 1
    let returned = returns
    DispatchQueue.main.asyncAfter(deadline: .now() + SystemSearchScreen.returnPatience) {
      [weak self] in
      guard let self = self, self.returns == returned else { return }
      self.returnsToResults = false
    }
  }

  /// Pose le focus sur la grille, qui le rend à l'affiche quittée
  /// (`remembersLastFocusedIndexPath`). Demandé au système de focus lui-même :
  /// le contrôleur de recherche est présenté par le conteneur, et c'est à lui,
  /// donc à son clavier, que le focus irait sinon.
  private func focusResults() {
    guard results.hasItems, let focus = UIFocusSystem(for: results.collectionView) else { return }
    focus.requestFocusUpdate(to: results.collectionView)
    focus.updateFocusIfNeeded()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed && !dismissedByHost {
      onDismissedBySystem?()
    }
  }

  override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if returnsToResults && results.hasItems {
      return [results.collectionView]
    }
    return [container]
  }

  @objc private func menuPressed() {
    onMenu?()
  }

  // Le même Retour, quand il arrive par la chaîne de réponse plutôt que par
  // le geste : le contrôleur de recherche est présenté par le conteneur, et
  // rien ne garantit que son clavier soit sous la vue qui porte le geste.
  // L'appui n'est pas transmis plus haut : UIKit y fermerait l'écran lui-même.
  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }) { return }
    super.pressesBegan(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }) {
      onMenu?()
      return
    }
    super.pressesEnded(presses, with: event)
  }

  /// Remplace ce que l'écran montre sous le clavier.
  func apply(_ content: SystemSearchContent) {
    results.apply(content)
  }

  /// Vide le champ sans le dire à Dart, qui repart déjà d'une recherche vide.
  func reset() {
    lastQuery = ""
    searchController.searchBar.text = ""
    returnsToResults = false
    returns += 1
  }

  // MARK: - UISearchControllerDelegate

  func didPresentSearchController(_ searchController: UISearchController) {
    if returnsToResults { focusResults() }
  }

  // MARK: - UISearchResultsUpdating

  func updateSearchResults(for searchController: UISearchController) {
    let query = searchController.searchBar.text ?? ""
    guard query != lastQuery else { return }
    lastQuery = query
    onQuery?(query)
  }
}

/// Les mesures de la grille, en points de tvOS (un écran de 1920 de large).
/// Ce sont celles du mur d'affiches de Flutter (`TvPosterWall`), dessiné sur
/// 1280 de large puis agrandi une fois et demie.
enum SystemSearchMetrics {
  /// Six affiches par ligne, comme une rangée de l'accueil.
  static let columns = 6

  /// `AppLayout.mediaRowGap`, 24.
  static let columnGap: CGFloat = 36

  /// Entre le bas d'une ligne et l'affiche de la suivante : la place de
  /// l'affiche soulevée, qui grandit d'un dixième vers le haut.
  static let rowGap: CGFloat = 44

  /// Entre la dernière ligne d'un rayon et le titre du suivant.
  static let sectionGap: CGFloat = 28

  /// Le titre d'un rayon, place de l'affiche soulevée comprise.
  static let headerHeight: CGFloat = 92

  /// `PosterCard.radius`, 12.
  static let posterRadius: CGFloat = 18

  /// `PosterCard.tvLift` : l'affiche focalisée grandit de 10 % depuis son
  /// pied (ADR-0118).
  static let lift: CGFloat = 1.10

  /// `PosterCard.overlayInset`, 9.
  static let overlayInset: CGFloat = 14
}

/// Les affiches sous le clavier, rangées par rayons.
final class SystemSearchResultsController: UIViewController, UICollectionViewDelegate {
  var onSelect: ((String) -> Void)?

  let collectionView: UICollectionView

  private let palette: SystemSearchPalette
  private let emptyView: SystemSearchEmptyView
  private var content = SystemSearchContent.empty
  private var itemsByID: [String: SystemSearchItem] = [:]
  private var dataSource: UICollectionViewDiffableDataSource<String, String>?

  var hasItems: Bool { !content.sections.isEmpty }

  init(palette: SystemSearchPalette) {
    self.palette = palette
    collectionView = UICollectionView(
      frame: .zero,
      collectionViewLayout: SystemSearchResultsController.makeLayout())
    emptyView = SystemSearchEmptyView(palette: palette)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SystemSearchResultsController ne se charge pas d'un storyboard")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    collectionView.backgroundColor = .clear
    collectionView.backgroundView = emptyView
    // L'affiche soulevée et son ombre débordent de leur case, et la grille
    // s'arrête aux marges de l'écran : rien ne doit les y couper.
    collectionView.clipsToBounds = false
    // Au retour d'une fiche, le focus retrouve l'affiche quittée.
    collectionView.remembersLastFocusedIndexPath = true
    collectionView.contentInsetAdjustmentBehavior = .always
    collectionView.delegate = self
    collectionView.register(
      SystemSearchPosterCell.self,
      forCellWithReuseIdentifier: SystemSearchPosterCell.reuseIdentifier)
    collectionView.register(
      SystemSearchHeaderView.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: SystemSearchHeaderView.reuseIdentifier)

    // Entre les marges de sécurité de tvOS, là où le clavier s'aligne aussi.
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
    ])

    let palette = self.palette
    let source = UICollectionViewDiffableDataSource<String, String>(
      collectionView: collectionView
    ) { [weak self] collectionView, indexPath, id in
      let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: SystemSearchPosterCell.reuseIdentifier, for: indexPath)
      if let poster = cell as? SystemSearchPosterCell, let item = self?.itemsByID[id] {
        poster.show(item, palette: palette)
      }
      return cell
    }
    source.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
      let view = collectionView.dequeueReusableSupplementaryView(
        ofKind: kind,
        withReuseIdentifier: SystemSearchHeaderView.reuseIdentifier,
        for: indexPath)
      if let header = view as? SystemSearchHeaderView, let self = self,
        indexPath.section < self.content.sections.count
      {
        header.show(self.content.sections[indexPath.section].title, palette: palette)
      }
      return view
    }
    dataSource = source
    render()
  }

  /// Remplace les rayons. Seul ce qui a changé est redessiné : une affiche
  /// qui reste garde sa place, son image et le focus.
  func apply(_ content: SystemSearchContent) {
    guard content != self.content else { return }
    self.content = content
    var items: [String: SystemSearchItem] = [:]
    for section in content.sections {
      for item in section.items {
        items[item.id] = item
      }
    }
    itemsByID = items
    render()
  }

  private func render() {
    guard let dataSource = dataSource else { return }
    var snapshot = NSDiffableDataSourceSnapshot<String, String>()
    for section in content.sections {
      snapshot.appendSections([section.id])
      snapshot.appendItems(section.items.map { $0.id }, toSection: section.id)
    }
    dataSource.apply(snapshot, animatingDifferences: false)
    refreshVisible()
    emptyView.show(title: content.emptyTitle, message: content.emptyMessage)
  }

  /// Ce qui a changé sans changer d'identifiant : le compte d'un rayon dans
  /// son titre, la pastille d'un titre qu'on vient de demander.
  private func refreshVisible() {
    let kind = UICollectionView.elementKindSectionHeader
    for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
      guard indexPath.section < content.sections.count,
        let header = collectionView.supplementaryView(forElementKind: kind, at: indexPath)
          as? SystemSearchHeaderView
      else { continue }
      header.show(content.sections[indexPath.section].title, palette: palette)
    }
    for cell in collectionView.visibleCells {
      guard let poster = cell as? SystemSearchPosterCell,
        let indexPath = collectionView.indexPath(for: poster),
        let id = dataSource?.itemIdentifier(for: indexPath),
        let item = itemsByID[id]
      else { continue }
      poster.show(item, palette: palette)
    }
  }

  // MARK: - UICollectionViewDelegate

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let id = dataSource?.itemIdentifier(for: indexPath) else { return }
    onSelect?(id)
  }

  // MARK: - Mise en page

  private static func makeLayout() -> UICollectionViewLayout {
    UICollectionViewCompositionalLayout { _, environment in
      let columns = CGFloat(SystemSearchMetrics.columns)
      let gap = SystemSearchMetrics.columnGap
      let width = environment.container.effectiveContentSize.width
      let cellWidth = max(1, ((width - gap * (columns - 1)) / columns).rounded(.down))
      let cellHeight = SystemSearchPosterCell.height(forWidth: cellWidth)

      let item = NSCollectionLayoutItem(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .absolute(cellWidth),
          heightDimension: .absolute(cellHeight)))
      let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .fractionalWidth(1),
          heightDimension: .absolute(cellHeight)),
        subitems: [item])
      group.interItemSpacing = .fixed(gap)

      let section = NSCollectionLayoutSection(group: group)
      section.interGroupSpacing = SystemSearchMetrics.rowGap
      section.contentInsets = NSDirectionalEdgeInsets(
        top: 0, leading: 0, bottom: SystemSearchMetrics.sectionGap, trailing: 0)
      section.boundarySupplementaryItems = [
        NSCollectionLayoutBoundarySupplementaryItem(
          layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(SystemSearchMetrics.headerHeight)),
          elementKind: UICollectionView.elementKindSectionHeader,
          alignment: .top)
      ]
      return section
    }
  }
}
