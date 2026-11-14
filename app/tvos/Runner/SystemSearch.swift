import Flutter
import UIKit

/// La recherche du système sur l'Apple TV (ADR-0129).
///
/// Demande de l'utilisateur, capture de YouTube à l'appui : « je veux la même
/// recherche que YouTube, on a le clavier ou on peut utiliser l'iPhone pour
/// noter ou sinon Siri et on a les résultats ici ». Ce clavier en ligne, sa
/// dictée et la saisie depuis un iPhone n'existent que dans
/// `UISearchController` : l'écran est donc natif, présenté par-dessus Flutter
/// comme l'est le lecteur (ADR-0105).
///
/// Dart reste le cerveau, par le canal `onyx/tv_search` : il reçoit ce qu'on
/// tape (`query`), cherche, et dit quoi afficher (`update`) ; il reçoit
/// l'affiche choisie (`select`) et ouvre sa fiche. Rien ici ne connaît la
/// bibliothèque ni le serveur, et aucun texte n'y est écrit : Dart les envoie
/// déjà traduits.
///
/// Ce fichier tient le canal et la présentation ; `SystemSearchScreen.swift`
/// l'écran, `SystemSearchPosterCell.swift` ses affiches.
final class SystemSearchChannel: NSObject {
  private let channel: FlutterMethodChannel

  /// L'écran, gardé entre deux présentations : on le retire quand une fiche
  /// s'ouvre, et il revient avec son texte, ses affiches et son défilement.
  private var screen: SystemSearchScreen?

  /// Ce que Dart veut : l'écran devant, ou retiré.
  private var wantsVisible = false

  /// Vrai quand l'écran retiré ne reviendra pas.
  private var releasesWhenHidden = false

  /// Vrai le temps d'une présentation ou d'un retrait : UIKit n'en mène
  /// qu'un à la fois, et refuse sans rien lever celui qui arrive pendant
  /// l'autre (constaté sur le lecteur natif, `NativePlayerPresenter`).
  private var transitioning = false
  private var transitions = 0
  private var retryScheduled = false
  private var retries = 0
  private var refusals = 0

  /// La réponse due au `present` de Dart : vrai une fois l'écran devant.
  private var pendingPresentation: FlutterResult?

  private static let retryDelay: TimeInterval = 0.1
  private static let maxRetries = 40
  private static let maxRefusals = 3

  /// Au-delà, la complétion d'une transition ne viendra plus : on relit
  /// l'état réel au lieu de l'attendre.
  private static let transitionPatience: TimeInterval = 2

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "onyx/tv_search", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "present":
      present(arguments, result: result)
    case "update":
      screen?.apply(SystemSearchContent(arguments))
      result(nil)
    case "hide":
      wantsVisible = false
      settle()
      result(nil)
    case "show":
      if let screen = screen, !releasesWhenHidden {
        // Au retour d'une fiche, la télécommande retrouve l'affiche quittée.
        screen.returnsToResults = true
        wantsVisible = true
        settle()
      }
      result(nil)
    case "close":
      wantsVisible = false
      releasesWhenHidden = true
      answerPresentation(false)
      settle()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Présentation

  private func present(_ arguments: [String: Any], result: @escaping FlutterResult) {
    answerPresentation(false)
    pendingPresentation = result

    let screen: SystemSearchScreen
    if let kept = self.screen {
      // Rouvert avant la fin du retrait précédent : le même écran, vidé.
      kept.reset()
      screen = kept
    } else {
      screen = makeScreen(arguments)
      self.screen = screen
    }
    screen.apply(SystemSearchContent(arguments["content"] as? [String: Any] ?? [:]))
    wantsVisible = true
    releasesWhenHidden = false
    refusals = 0
    retries = 0
    settle()
  }

  private func makeScreen(_ arguments: [String: Any]) -> SystemSearchScreen {
    let screen = SystemSearchScreen(
      palette: SystemSearchPalette(arguments["colors"] as? [String: Any] ?? [:]),
      placeholder: arguments["placeholder"] as? String ?? "")
    screen.onQuery = { [weak self] query in
      self?.channel.invokeMethod("query", arguments: query)
    }
    screen.onSelect = { [weak self] id in
      self?.channel.invokeMethod("select", arguments: id)
    }
    screen.onMenu = { [weak self] in
      self?.closedByRemote()
    }
    screen.onDismissedBySystem = { [weak self, weak screen] in
      guard let self = self, let screen = screen, self.screen === screen else { return }
      // UIKit a retiré l'écran de lui-même : Dart doit refermer sa page, et
      // Flutter retrouver le focus.
      self.screen = nil
      self.wantsVisible = false
      self.transitioning = false
      self.channel.invokeMethod("closed", arguments: nil)
      Self.returnFocusToFlutter()
    }
    return screen
  }

  /// Retour sur la télécommande : l'écran se referme, Dart dépile sa page.
  private func closedByRemote() {
    guard wantsVisible else { return }
    wantsVisible = false
    releasesWhenHidden = true
    channel.invokeMethod("closed", arguments: nil)
    settle()
  }

  /// Rapproche l'écran de ce que Dart veut, une transition à la fois.
  private func settle() {
    guard !transitioning, let screen = screen else { return }
    if screen.isBeingPresented || screen.isBeingDismissed {
      retrySoon()
      return
    }
    let shown = screen.presentingViewController != nil
    if wantsVisible == shown {
      retries = 0
      if shown {
        answerPresentation(true)
      } else if releasesWhenHidden {
        self.screen = nil
      }
      return
    }
    if wantsVisible {
      show(screen)
    } else {
      hide(screen)
    }
  }

  private func show(_ screen: SystemSearchScreen) {
    guard let host = Self.topController(), host.view.window != nil else {
      giveUp()
      return
    }
    // Une fiche native encore en train de se fermer : UIKit refuserait.
    if let leaving = host.presentedViewController, leaving.isBeingDismissed {
      retrySoon()
      return
    }
    transitioning = true
    screen.dismissedByHost = false
    host.present(screen, animated: true) { [weak self, weak screen] in
      guard let self = self else { return }
      self.transitioning = false
      if let screen = screen, screen.presentingViewController == nil {
        // UIKit ne lève rien quand il refuse une présentation.
        self.refusals += 1
        if self.refusals >= Self.maxRefusals {
          self.giveUp()
          return
        }
      } else {
        self.refusals = 0
      }
      self.settle()
    }
    watchTransition()
  }

  private func hide(_ screen: SystemSearchScreen) {
    guard let presenting = screen.presentingViewController else { return }
    transitioning = true
    screen.dismissedByHost = true
    presenting.dismiss(animated: true) { [weak self] in
      guard let self = self else { return }
      self.transitioning = false
      Self.returnFocusToFlutter()
      self.settle()
    }
    watchTransition()
  }

  /// L'écran ne peut pas être montré : Dart l'apprend, par la réponse à
  /// `present` s'il l'attend encore, sinon par `closed`, et reprend la main.
  private func giveUp() {
    wantsVisible = false
    releasesWhenHidden = true
    refusals = 0
    retries = 0
    if pendingPresentation != nil {
      answerPresentation(false)
    } else {
      channel.invokeMethod("closed", arguments: nil)
    }
    if let screen = screen, screen.presentingViewController == nil {
      self.screen = nil
    }
  }

  private func answerPresentation(_ shown: Bool) {
    guard let answer = pendingPresentation else { return }
    pendingPresentation = nil
    answer(shown)
  }

  private func retrySoon() {
    guard !retryScheduled else { return }
    retries += 1
    if retries > Self.maxRetries {
      retries = 0
      if wantsVisible { giveUp() }
      return
    }
    retryScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
      guard let self = self else { return }
      self.retryScheduled = false
      self.settle()
    }
  }

  private func watchTransition() {
    transitions += 1
    let started = transitions
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionPatience) { [weak self] in
      guard let self = self, self.transitioning, self.transitions == started else { return }
      self.transitioning = false
      self.settle()
    }
  }

  /// Le contrôleur visible le plus haut de la scène : la racine est celui de
  /// Flutter, mais une feuille déjà présentée refuserait une seconde
  /// présentation depuis la racine.
  private static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window =
      scenes.compactMap { $0.keyWindow }.first
      ?? scenes.flatMap { $0.windows }.first { !$0.isHidden }
    guard var top = window?.rootViewController else { return nil }
    while let presented = top.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }

  /// Une à trois secondes de focus vide quand rien ne le redemandait, mesuré
  /// sur le lecteur natif : on le redemande à la fin de chaque retrait.
  private static func returnFocusToFlutter() {
    guard let host = topController() else { return }
    host.setNeedsFocusUpdate()
    host.updateFocusIfNeeded()
  }
}

// MARK: - Ce que Dart envoie

/// Une affiche, telle que Dart la décrit.
struct SystemSearchItem: Equatable {
  let id: String
  let title: String
  let subtitle: String
  let poster: URL?
  let badge: String?
  let badgeTint: UIColor?
  let dimmed: Bool
  let progress: Double?
  let watched: Bool

  init?(_ map: [String: Any]) {
    guard let id = map["id"] as? String, !id.isEmpty else { return nil }
    self.id = id
    title = map["title"] as? String ?? ""
    subtitle = map["subtitle"] as? String ?? ""
    poster = (map["poster"] as? String).flatMap { URL(string: $0) }
    badge = map["badge"] as? String
    badgeTint = (map["badgeTint"] as? NSNumber).map { UIColor(argb: $0.int64Value) }
    dimmed = map["dimmed"] as? Bool ?? false
    progress = (map["progress"] as? NSNumber)?.doubleValue
    watched = map["watched"] as? Bool ?? false
  }
}

/// Un rayon : son titre et ses affiches.
struct SystemSearchSection: Equatable {
  let id: String
  let title: String
  let items: [SystemSearchItem]
}

/// Ce que l'écran montre sous le clavier.
struct SystemSearchContent: Equatable {
  let sections: [SystemSearchSection]
  let emptyTitle: String?
  let emptyMessage: String?

  static let empty = SystemSearchContent([:])

  /// Chaque identifiant n'est gardé qu'une fois : la source de données de la
  /// grille s'arrête net sur un doublon, et un message mal formé ne doit pas
  /// fermer l'app.
  init(_ map: [String: Any]) {
    var sectionIDs = Set<String>()
    var itemIDs = Set<String>()
    var kept: [SystemSearchSection] = []
    for raw in map["sections"] as? [[String: Any]] ?? [] {
      guard let id = raw["id"] as? String, sectionIDs.insert(id).inserted else { continue }
      let items = (raw["items"] as? [[String: Any]] ?? [])
        .compactMap { SystemSearchItem($0) }
        .filter { itemIDs.insert($0.id).inserted }
      guard !items.isEmpty else { continue }
      kept.append(SystemSearchSection(id: id, title: raw["title"] as? String ?? "", items: items))
    }
    sections = kept
    emptyTitle = map["emptyTitle"] as? String
    emptyMessage = map["emptyMessage"] as? String
  }
}

/// Les couleurs de l'app, que Dart envoie sous leur nom d'`AppColors`. Celles
/// d'ici ne servent que si l'une manque au message.
struct SystemSearchPalette {
  let background: UIColor
  let surfaceElevated: UIColor
  let textPrimary: UIColor
  let textSecondary: UIColor
  let textMuted: UIColor
  let progress: UIColor
  let success: UIColor
  let unavailableTint: UIColor

  init(_ map: [String: Any]) {
    func color(_ name: String, _ fallback: Int64) -> UIColor {
      UIColor(argb: (map[name] as? NSNumber)?.int64Value ?? fallback)
    }
    background = color("background", 0xFF0A_0A0A)
    surfaceElevated = color("surfaceElevated", 0xFF1C_1C1C)
    textPrimary = color("textPrimary", 0xFFF5_F5F7)
    textSecondary = color("textSecondary", 0xFFA1_A1A6)
    textMuted = color("textMuted", 0xFF6E_6E73)
    progress = color("progress", 0xFF0A_84FF)
    success = color("success", 0xFF30_D158)
    unavailableTint = color("unavailableTint", 0x7300_0000)
  }
}

extension UIColor {
  /// Une couleur de Dart : 0xAARRGGBB.
  convenience init(argb: Int64) {
    let value = UInt32(truncatingIfNeeded: argb)
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: CGFloat((value >> 24) & 0xFF) / 255)
  }
}
