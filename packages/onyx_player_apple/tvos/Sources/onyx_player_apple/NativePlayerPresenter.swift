#if os(tvOS)
  import AVFoundation
  import AVKit
  import AetherEngine
  import Combine
  import CoreMedia
  import UIKit

  /// L'écran de lecture natif de l'Apple TV : un `AVPlayerViewController`
  /// présenté par-dessus Flutter, qui joue l'`AVPlayer` du moteur.
  ///
  /// Le présentateur n'a pas d'état à lui : Dart reste le cerveau, envoie une
  /// spec complète à chaque changement et reçoit les gestes de l'utilisateur
  /// en événements. Voir le compte rendu du spike
  /// (`docs/agents/spike-native-tv-player.md`).
  @MainActor
  final class NativePlayerPresenter: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    private let playerId: Int64
    private let engine: AetherEngine
    private let send: (OnyxAppleNativeEvent) -> Void

    private var controller: AVPlayerViewController?
    private var subscriptions = Set<AnyCancellable>()
    /// Posé dès qu'une fermeture part d'ici (Dart, ou la route logicielle) :
    /// la fin de transition qui suit ne doit pas se faire passer pour un Menu.
    private var closingFromHere = false

    private var spec: OnyxAppleNativeSpec?
    /// L'affiche déjà téléchargée, pour qu'une spec qui ne change que les
    /// menus ne la retélécharge pas.
    private var poster: (url: String, jpeg: Data)?
    private var posterTask: Task<Void, Never>?
    private var posterRequested: String?

    init(playerId: Int64, engine: AetherEngine, send: @escaping (OnyxAppleNativeEvent) -> Void) {
      self.playerId = playerId
      self.engine = engine
      self.send = send
    }

    var isPresented: Bool { controller != nil }

    // MARK: - Commandes

    func present(_ spec: OnyxAppleNativeSpec) {
      if controller != nil {
        update(spec)
        return
      }
      // Sur la route logicielle, l'image part dans une couche que rien
      // n'affiche : AVKit montrerait une roue sur fond noir, son joué (#298).
      guard engine.videoRoute != .software else {
        emit(.unavailable, reason: .softwareRoute)
        return
      }
      guard let presenting = Self.presentingController(), presenting.view.window != nil else {
        emit(.unavailable, reason: .presentationFailed)
        return
      }

      let controller = AVPlayerViewController()
      controller.delegate = self
      // Le moteur écrit seul les critères d'affichage, avant d'affecter l'item :
      // tvOS 26.5 refuse sinon les variantes HDR (README AetherEngine, « Host
      // setup on tvOS »).
      controller.appliesPreferredDisplayCriteriaAutomatically = false
      controller.player = engine.currentAVPlayer
      self.controller = controller
      closingFromHere = false
      apply(spec)
      observe()

      presenting.present(controller, animated: true) { [weak self, weak controller] in
        MainActor.assumeIsolated {
          guard let self, let controller, self.controller === controller else { return }
          // UIKit ne lève rien quand il refuse une présentation (contrôleur
          // déjà occupé, hors fenêtre) : il journalise et passe.
          if controller.presentingViewController == nil {
            self.teardown()
            self.emit(.unavailable, reason: .presentationFailed)
          }
        }
      }
    }

    func update(_ spec: OnyxAppleNativeSpec) {
      guard controller != nil else { return }
      apply(spec)
    }

    func dismiss() {
      close { [weak self] in self?.emit(.dismissed, reason: .requested) }
    }

    /// Le lecteur est détruit : Dart n'écoute plus, rien à lui dire.
    func release() {
      close(then: nil)
    }

    // MARK: - Spec

    private func apply(_ spec: OnyxAppleNativeSpec) {
      guard let controller else { return }
      self.spec = spec
      controller.transportBarCustomMenuItems = spec.menus.map(menu)
      controller.contextualActions = spec.actions.map(action)
      applyMetadata()
      fetchPosterIfNeeded(spec.posterUrl)
    }

    /// Dart reste maître de l'état coché : un choix n'en change rien ici, il
    /// attend la spec suivante.
    private func menu(_ menu: OnyxAppleNativeMenu) -> UIMenu {
      let menuId = menu.id
      let children = menu.options.map { option in
        UIAction(title: option.label, state: option.selected ? .on : .off) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.emit(.menuSelected, menuId: menuId, optionId: option.id)
          }
        }
      }
      return UIMenu(title: menu.label, children: children)
    }

    private func action(_ action: OnyxAppleNativeAction) -> UIAction {
      let actionId = action.id
      return UIAction(title: action.label) { [weak self] _ in
        MainActor.assumeIsolated { self?.emit(.action, actionId: actionId) }
      }
    }

    /// Le moteur remplace l'item à chaque rechargement (audio, qualité) et
    /// rejoue ces métadonnées sur chacun : les poser sur l'item courant
    /// les perdrait au premier changement de piste.
    private func applyMetadata() {
      guard let spec else { return }
      var items = [Self.metadata(.commonIdentifierTitle, spec.title)]
      if let subtitle = spec.subtitle {
        items.append(Self.metadata(.iTunesMetadataTrackSubTitle, subtitle))
      }
      if let overview = spec.overview {
        items.append(Self.metadata(.commonIdentifierDescription, overview))
      }
      if let poster, poster.url == spec.posterUrl {
        let artwork = AVMutableMetadataItem()
        artwork.identifier = .commonIdentifierArtwork
        artwork.value = poster.jpeg as NSData
        artwork.dataType = kCMMetadataBaseDataType_JPEG as String
        artwork.extendedLanguageTag = "und"
        items.append(artwork)
      }
      engine.setExternalMetadata(items)
    }

    private func fetchPosterIfNeeded(_ value: String?) {
      guard let value, poster?.url != value, posterRequested != value, let url = URL(string: value)
      else { return }
      posterTask?.cancel()
      posterRequested = value
      posterTask = Task { [weak self] in
        do {
          let (data, _) = try await URLSession.shared.data(from: url)
          // Réencodé en JPEG : AVKit ne lit que le type déclaré, et le serveur
          // peut servir du WebP.
          guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) else { return }
          guard let self, !Task.isCancelled else { return }
          self.poster = (value, jpeg)
          self.applyMetadata()
        } catch {
          // Une affiche qui manque laisse le panneau d'infos sans image, rien
          // de plus : le titre et le synopsis y sont déjà.
          NSLog("Onyx: affiche du lecteur natif indisponible : \(error.localizedDescription)")
        }
      }
    }

    private static func metadata(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
      let item = AVMutableMetadataItem()
      item.identifier = identifier
      item.value = value as NSString
      item.extendedLanguageTag = "und"
      return item
    }

    // MARK: - Moteur

    /// Les `@Published` émettent la nouvelle valeur *avant* de l'écrire : on
    /// lit donc celle reçue, jamais la propriété du moteur.
    private func observe() {
      subscriptions.removeAll()
      engine.$currentAVPlayer
        .sink { [weak self] player in
          MainActor.assumeIsolated { self?.playerChanged(player) }
        }
        .store(in: &subscriptions)
      engine.$videoRoute
        .sink { [weak self] route in
          MainActor.assumeIsolated {
            if route == .software { self?.fallBackToFlutter() }
          }
        }
        .store(in: &subscriptions)
      engine.systemCaptionRequest
        .receive(on: DispatchQueue.main)
        .sink { [weak self] request in
          MainActor.assumeIsolated { self?.captionRequested(request) }
        }
        .store(in: &subscriptions)
    }

    /// Le même `AVPlayer` survit à un changement d'audio ou de qualité, un
    /// nouveau naît après `stop()` (épisode suivant). Republier la même
    /// instance relancerait l'enregistrement AVKit : seule l'identité compte.
    ///
    /// Nil entre deux épisodes (route `none`) ne ferme rien : le suivant
    /// arrive juste derrière. Nil sur la route logicielle, c'est
    /// `fallBackToFlutter` qui s'en charge.
    private func playerChanged(_ player: AVPlayer?) {
      guard let controller, controller.player !== player else { return }
      controller.player = player
    }

    /// Le moteur peut passer en route logicielle en cours de film (un AVPlayer
    /// qui refuse la source, AE#561) : Dart reprend l'écran Flutter.
    private func fallBackToFlutter() {
      guard controller != nil, !closingFromHere else { return }
      emit(.unavailable, reason: .softwareRoute)
      close(then: nil)
    }

    /// AVKit ou les sous-titres automatiques du système ont choisi une piste :
    /// le moteur l'a déjà désélectionnée et publie la demande (Sodalite#65).
    /// Dart décide et rappelle `selectSubtitleTrack`.
    private func captionRequested(_ request: SystemCaptionRequest) {
      guard controller != nil else { return }
      let wanted = CaptionLanguage.normalized(request.language)
      guard let track = engine.subtitleTracks.first(where: { CaptionLanguage.normalized($0.language) == wanted })
      else {
        NSLog("Onyx: sous-titre demandé par le système sans piste correspondante (\(request.language ?? "sans langue"))")
        return
      }
      emit(.subtitleSelected, trackId: String(track.id))
    }

    // MARK: - Fermeture

    private func close(then completion: (() -> Void)?) {
      guard let controller else { return }
      closingFromHere = true
      guard controller.presentingViewController != nil else {
        teardown()
        completion?()
        return
      }
      controller.dismiss(animated: true) { [weak self] in
        MainActor.assumeIsolated {
          self?.teardown()
          completion?()
        }
      }
    }

    private func teardown() {
      subscriptions.removeAll()
      posterTask?.cancel()
      posterTask = nil
      posterRequested = nil
      controller?.player = nil
      controller?.delegate = nil
      controller = nil
      spec = nil
    }

    // MARK: - AVPlayerViewControllerDelegate

    func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
      true
    }

    /// Menu sur la télécommande. Émis à la fin de la transition seulement :
    /// c'est là que le focus revient à Flutter (une à trois secondes plus tard,
    /// mesuré dans le spike).
    func playerViewControllerDidEndDismissalTransition(_ playerViewController: AVPlayerViewController) {
      guard playerViewController === controller, !closingFromHere else { return }
      teardown()
      emit(.dismissed, reason: .userDismissed)
    }

    // MARK: - Événements

    private func emit(
      _ kind: OnyxAppleNativeEventKind,
      actionId: String? = nil, menuId: String? = nil, optionId: String? = nil,
      trackId: String? = nil, reason: OnyxAppleNativeReason? = nil
    ) {
      send(
        OnyxAppleNativeEvent(
          playerId: playerId, kind: kind, actionId: actionId, menuId: menuId,
          optionId: optionId, trackId: trackId, reason: reason))
    }

    /// Le contrôleur visible le plus haut de la scène de flutter-tvos : la
    /// racine est le `FlutterViewController`, mais une feuille déjà présentée
    /// refuserait une seconde présentation depuis la racine.
    private static func presentingController() -> UIViewController? {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let window =
        scenes.compactMap(\.keyWindow).first
        ?? scenes.flatMap(\.windows).first { !$0.isHidden }
      guard var top = window?.rootViewController else { return nil }
      while let presented = top.presentedViewController, !presented.isBeingDismissed {
        top = presented
      }
      return top
    }
  }

  /// Rapproche la langue BCP 47 d'AVKit (`fr`) de celle du conteneur (`fre`,
  /// `fra`) : `SystemCaptionRequest` ne porte que la langue, pas la piste.
  enum CaptionLanguage {
    /// Matroska écrit les codes ISO 639-2/B, qu'ICU ne résout pas.
    private static let terminologicalByBibliographic: [String: String] = [
      "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho",
      "cze": "ces", "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu",
      "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa",
      "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]

    /// Nil pour une piste sans langue (ou `und`), qui ne correspond qu'à une
    /// demande sans langue.
    static func normalized(_ language: String?) -> String? {
      guard var raw = language?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty, raw != "und"
      else { return nil }
      raw = String(raw.split(separator: "-").first ?? Substring(raw))
      raw = terminologicalByBibliographic[raw] ?? raw
      return Locale.LanguageCode(raw).identifier(.alpha3) ?? raw
    }
  }
#endif
