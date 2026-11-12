import AVFoundation
import Flutter
import UIKit

/// L'hôte de l'app sur l'Apple TV (ADR-0028).
///
/// Généré par `flutter-tvos create`, puis complété de ce que l'hôte iOS fait
/// déjà : la session audio d'un lecteur vidéo, et le canal `onyx/device` que
/// `TvMode`, `ClientIdentity` et la session AVPlayer interrogent.
@main
class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureAudioSession()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Le SDK tvOS 27 exige cycle de vie UIScene : le moteur naît avec la scène
  /// (storyboard `Main`) et les plugins s'inscrivent ici, comme sur iOS.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnyxDevice") {
      registerDeviceChannel(messenger: registrar.messenger())
    }
  }

  /// Le pendant tvOS du canal `onyx/device` d'Android et d'iOS.
  ///
  /// - `isTelevision` : toujours vrai ici.
  /// - `deviceName` : le nom que l'utilisateur a donné à son Apple TV, montré
  ///   sur le téléphone qui approuve l'appairage.
  /// - `appVersion` : `package_info_plus` n'a pas de portage tvOS compatible
  ///   avec la version épinglée, la version se lit donc ici.
  /// - `setKeepScreenOn` : l'économiseur d'écran ne sait pas qu'une texture
  ///   Flutter est un film ; la session AVPlayer le suspend pendant la lecture.
  /// - `memoryProfile` : la mémoire et le modèle, pour que `DeviceHardware`
  ///   reconnaisse une Apple TV HD (A8, 2 Go) et passe l'interface en mode
  ///   léger.
  private func registerDeviceChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "onyx/device", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isTelevision":
        result(true)
      case "memoryProfile":
        result(AppDelegate.deviceMemoryProfile())
      case "deviceName":
        result(UIDevice.current.name)
      case "appVersion":
        result(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
      case "setKeepScreenOn":
        UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Le pendant de `memoryProfile` sur Android, plus le modèle (`AppleTV5,3`
  /// pour une Apple TV HD) : la mémoire seule ne dit pas l'âge de la puce.
  private static func deviceMemoryProfile() -> [String: Any] {
    var info = utsname()
    uname(&info)
    let model = withUnsafeBytes(of: &info.machine) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
    return [
      "totalMemoryMb": Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)),
      "isLowRamDevice": false,
      "model": model,
    ]
  }

  /// Même raison que sur iOS (ADR-0011 §3) : sans la catégorie `.playback`,
  /// le son d'un film suit les règles d'une app d'ambiance.
  ///
  /// La catégorie seulement, jamais `setActive(true)` : activer la session au
  /// lancement fige la route audio sur ce que le HDMI annonce à cet instant,
  /// la stéréo quand la liaison est au repos, et plus aucun appel ne la
  /// relève ensuite. Un film en 5.1 était alors mixé en stéréo. C'est
  /// l'écran de lecture qui active la session, au moment où tvOS négocie la
  /// route (AetherEngine, issue #24).
  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    } catch {
      NSLog("Onyx: configuration AVAudioSession impossible : \(error)")
    }
  }
}

/// Délégué de scène par défaut de Flutter, requis par le SDK tvOS 27.
class SceneDelegate: FlutterSceneDelegate {}
