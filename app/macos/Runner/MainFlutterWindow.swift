import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Frameless chrome: keep traffic lights, hide title bar strip.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    NowPlayingController.shared.register(messenger: flutterViewController.engine.binaryMessenger)
    FloatingWindowController.shared.register(
      window: self,
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}

/// Fait flotter la fenêtre au-dessus de tout, y compris d'une app d'un autre
/// bureau en plein écran : c'est ce qu'il faut à l'image dans l'image du
/// lecteur (voir `desktop_picture_in_picture_io.dart`).
///
/// `canJoinAllSpaces` et `fullScreenAuxiliary` ne suffisent pas pour une app
/// qui a une icône dans le Dock : macOS ne montre alors la fenêtre que sur son
/// bureau d'origine. Elle passe devant un plein écran seulement si l'app est
/// « accessoire », sans Dock ni barre de menus. L'app le devient donc le temps
/// de l'image dans l'image, et redevient normale ensuite.
///
/// Le serveur de fenêtres ne relit ces réglages qu'à la remise à l'écran de la
/// fenêtre, et une fenêtre déjà élevée au-dessus des autres (le « toujours au
/// premier plan » de `window_manager`, posé juste avant) tant que l'app avait
/// son Dock reste attachée à son bureau. D'où, dans cet ordre : retour au
/// niveau normal, passage en accessoire, retrait, élévation, remise à l'écran.
/// Essayé sur un bureau plein écran : sans l'un de ces pas, elle n'y était pas.
final class FloatingWindowController {
  static let shared = FloatingWindowController()

  private weak var window: NSWindow?
  private var floating = false
  private var spaceObserver: NSObjectProtocol?
  private var hop: SpaceArrivalHop?

  func register(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    let channel = FlutterMethodChannel(
      name: "onyx/floating_window",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setFloating" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      self?.setFloating(arguments?["floating"] as? Bool ?? false)
      result(nil)
    }
  }

  private func setFloating(_ on: Bool) {
    guard let window = window, on != floating else { return }
    floating = on
    if on {
      window.level = .normal
      NSApp.setActivationPolicy(.accessory)
      window.collectionBehavior.remove(.moveToActiveSpace)
      window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
      window.orderOut(nil)
      window.level = .statusBar
      window.orderFrontRegardless()
      hop = SpaceArrivalHop(window: window)
      spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.hop?.play()
      }
    } else {
      if let spaceObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
      }
      spaceObserver = nil
      // Remise en place avant que Flutter ne rende sa taille à la fenêtre.
      hop?.stop()
      hop = nil
      NSApp.setActivationPolicy(.regular)
      window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
      window.level = .normal
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }
  }
}

/// Le petit saut de la fenêtre d'image dans l'image quand elle arrive sur un
/// autre bureau : sans lui, elle reste figée pendant que le bureau glisse
/// dessous, et rien ne dit qu'elle a suivi.
///
/// macOS ne prévient qu'à la fin du glissement, et ne dit pas dans quel sens :
/// la fenêtre part donc de sa place, se soulève vers le milieu de l'écran et y
/// retombe en rebondissant (ressort amorti). Seule l'origine bouge : la taille
/// ne change pas, Flutter n'a rien à redessiner. Rien du tout si le Mac est
/// réglé pour réduire les animations, ou si la fenêtre est tenue à la souris.
final class SpaceArrivalHop: NSObject {
  /// Hauteur du saut, en points.
  private static let height: CGFloat = 12
  /// Raideur et amortissement du ressort : un rebond bien visible, puis un
  /// second à peine, posé en sept dixièmes de seconde.
  private static let stiffness = 12.0
  private static let damping = 0.5
  private static let duration = 0.7

  private weak var window: NSWindow?
  private var link: CADisplayLink?
  private var rest: NSPoint = .zero
  private var direction: CGFloat = 1
  private var start: CFTimeInterval = 0

  init(window: NSWindow) {
    self.window = window
  }

  func play() {
    guard let window, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    // Un saut déjà en cours va à son terme : le relancer la ferait retomber
    // d'un coup.
    guard link == nil, NSEvent.pressedMouseButtons & 1 == 0 else { return }
    rest = window.frame.origin
    let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
    direction = window.frame.midY < screen.midY ? 1 : -1
    start = CACurrentMediaTime()
    let link = window.displayLink(target: self, selector: #selector(step))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  func stop() {
    guard let link else { return }
    link.invalidate()
    self.link = nil
    window?.setFrameOrigin(rest)
  }

  @objc private func step(_ link: CADisplayLink) {
    guard let window else { return stop() }
    // Attrapée à la souris : elle reste où on la pose.
    if NSEvent.pressedMouseButtons & 1 != 0 {
      link.invalidate()
      self.link = nil
      return
    }
    let t = link.targetTimestamp - start
    guard t < Self.duration else { return stop() }
    window.setFrameOrigin(
      NSPoint(x: rest.x, y: rest.y + direction * Self.height * Self.offset(at: t)))
  }

  /// Le déplacement du ressort parti de sa place avec une impulsion, ramené
  /// à 1 au sommet du premier rebond.
  private static func offset(at t: Double) -> Double {
    let decay = damping * stiffness
    let frequency = stiffness * (1 - damping * damping).squareRoot()
    let peak = atan(frequency / decay) / frequency
    let curve = { (t: Double) in exp(-decay * t) * sin(frequency * t) }
    return curve(t) / curve(peak)
  }
}
