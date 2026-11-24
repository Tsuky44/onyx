import AudioToolbox
import Flutter
import Foundation

/// Les sons de navigation de tvOS, joués à la demande de Dart (ADR
/// `2026-11-23-fytroz-sons-de-navigation-apple-tv`).
///
/// tvOS ne joue son clic que pour un déplacement mené par le moteur de focus
/// d'UIKit. Ici c'est Flutter qui déplace le focus : UIKit ne voit rien
/// bouger, et l'app était muette. Aucune API publique ne joue ce clic à la
/// demande ; on rejoue donc les fichiers de son du système lui-même, par
/// System Sound Services (`AudioServicesPlaySystemSound`, tvOS 9).
///
/// Dart décide de tout (quand, à quelle cadence, jamais pendant un film) par
/// le canal `onyx/tv_navigation_sound` ; cet hôte ne sait que charger trois
/// sons et les jouer.
///
/// Pas d'`AVAudioPlayer` : il passerait par la session audio de l'app, que
/// seul le lecteur active (voir `configureAudioSession`), et pourrait couper
/// ou baisser ce qui joue ailleurs. System Sound Services joue hors de cette
/// session (Apple : « not subject to configuration using your audio
/// session »).
///
/// Rien ici ne peut être écouté sans une vraie Apple TV : un son absent ou
/// refusé laisse l'app muette, jamais en panne.
final class NavigationSoundChannel: NSObject {
  /// Le dossier des sons d'interface du système. Lus sur place, jamais
  /// copiés : ces fichiers sont à Apple, ils n'entrent ni dans le dépôt ni
  /// dans l'app.
  private static let directory = "/System/Library/Audio/UISounds/"

  private let channel: FlutterMethodChannel

  /// Les trois sons, chargés une fois (`load`) : jouer n'alloue rien.
  private var move: SystemSoundID = 0
  private var push: SystemSoundID = 0
  private var pop: SystemSoundID = 0

  /// D'où vient chaque son, `file` ou `id`, rendu à Dart qui l'écrit dans le
  /// journal de l'app : c'est ce qu'on lira si l'Apple TV reste muette.
  private var sources: [String: String] = [:]

  private var loaded = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "onyx/tv_navigation_sound", binaryMessenger: messenger)
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
    // Au premier appel seulement, d'ordinaire `prepare` : une app dont le
    // réglage est coupé ne charge rien.
    load()
    switch call.method {
    case "prepare":
      result(sources)
    case "move":
      AudioServicesPlaySystemSound(move)
      result(nil)
    case "push":
      AudioServicesPlaySystemSound(push)
      result(nil)
    case "pop":
      AudioServicesPlaySystemSound(pop)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func load() {
    if loaded { return }
    loaded = true
    move = register("move", file: "focus_change_small.caf", fallback: 1127)
    push = register("push", file: "navigation_push.caf", fallback: 1128)
    pop = register("pop", file: "navigation_pop.caf", fallback: 1129)
  }

  /// Le son du fichier `file` du système, à défaut celui que le système
  /// range lui-même sous l'identifiant `fallback`.
  ///
  /// Le fichier d'abord : son nom dit ce qu'on joue. Les identifiants fixes
  /// ne sont documentés nulle part ; ceux-ci sont ceux que la table des sons
  /// d'iOS donne aux mêmes fichiers (`FocusChangeSmall`, `NavigationPush`,
  /// `NavigationPop`). Ils servent si le dossier a bougé ou si le bac à sable
  /// refuse la lecture, et ne jouent rien si le système ne les connaît pas.
  private func register(_ name: String, file: String, fallback: SystemSoundID) -> SystemSoundID {
    let path = NavigationSoundChannel.directory + file
    if FileManager.default.fileExists(atPath: path) {
      var created: SystemSoundID = 0
      let status = AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &created)
      if status == kAudioServicesNoError {
        sources[name] = "file"
        return created
      }
      NSLog("Onyx: son de navigation \(file) refusé (statut \(status))")
    } else {
      NSLog("Onyx: son de navigation \(file) absent de ce système")
    }
    sources[name] = "id"
    return fallback
  }
}
