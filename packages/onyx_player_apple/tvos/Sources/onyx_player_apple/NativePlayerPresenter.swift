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
  /// (`docs/agents/spike-native-tv-player.md`) et l'inventaire de parité
  /// (`docs/agents/native-tv-parity.md`).
  @MainActor
  final class NativePlayerPresenter: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    private let playerId: Int64
    private let engine: AetherEngine
    private let stats: @MainActor () -> OnyxApplePlaybackStats?
    private let send: (OnyxAppleNativeEvent) -> Void

    private var controller: AVPlayerViewController?
    private var subscriptions = Set<AnyCancellable>()
    /// Posé dès qu'une fermeture part d'ici (Dart, ou la route logicielle) :
    /// la fin de transition qui suit ne doit pas se faire passer pour un Menu.
    private var closingFromHere = false
    /// Menu a lancé la fermeture et Dart le sait déjà : la fin de la
    /// transition fait le ménage sans le redire.
    private var userDismissalAnnounced = false
    /// La spec d'une présentation qui attend que l'écran précédent ait fini
    /// de se fermer ([present]).
    private var pendingSpec: OnyxAppleNativeSpec?

    private var spec: OnyxAppleNativeSpec?
    /// L'affiche déjà téléchargée, pour qu'une spec qui ne change que les
    /// menus ne la retélécharge pas.
    private var poster: (url: String, jpeg: Data)?
    private var posterTask: Task<Void, Never>?
    private var posterRequested: String?

    /// Suit les choix du menu Sous-titres d'AVKit sur l'item courant.
    private var selectionObserver: NSObjectProtocol?
    /// La dernière option `legible` vue sur cet item : un item neuf commence
    /// sans sélection, et ce n'est pas un « Désactivé ».
    private var lastLegible: AVMediaSelectionOption?

    /// Les sous-titres image, qu'AVKit ne peint pas : une couche à nous dans
    /// son `contentOverlayView`, le temps de la présentation.
    private var bitmapSubtitles: NativeBitmapSubtitles?
    /// L'annonce de Regarder ensemble, posée au-dessus des sous-titres image.
    private var overlay: NativeOverlayView?
    private var panels: NativeInfoPanels?
    private var nextUp: NativeNextUp?
    private lazy var transport = NativeTransportWatch { [weak self] playing, positionMs in
      self?.noteActivity()
      self?.emit(.transport, playing: playing, positionMs: positionMs)
    }

    /// La question affichée, et la dernière à laquelle l'utilisateur a
    /// répondu : une spec qui la redit encore ne la repose pas.
    private var prompt: (id: String, alert: UIAlertController)?
    private var answeredPrompt: String?
    private var lastActivity = Date.distantPast

    init(
      playerId: Int64, engine: AetherEngine, stats: @escaping @MainActor () -> OnyxApplePlaybackStats?,
      send: @escaping (OnyxAppleNativeEvent) -> Void
    ) {
      self.playerId = playerId
      self.engine = engine
      self.stats = stats
      self.send = send
    }

    var isPresented: Bool { controller != nil }

    // MARK: - Commandes

    /// Le nombre d'essais, espacés de [presentRetry], qu'une présentation
    /// accorde à l'écran précédent pour finir de se fermer : trois secondes,
    /// bien plus que la transition d'AVKit.
    private static let presentAttempts = 30
    private static let presentRetry: TimeInterval = 0.1

    func present(_ spec: OnyxAppleNativeSpec) {
      present(spec, attempt: 0)
    }

    private func present(_ spec: OnyxAppleNativeSpec, attempt: Int) {
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
      // À l'épisode suivant, l'écran du précédent est encore en train de se
      // fermer : UIKit refuse une présentation pendant une fermeture, sans
      // rien lever ni toujours appeler la complétion. L'écran restait alors
      // noir, son joué, ou le natif se retirait pour tout l'épisode. On
      // attend la fin de la transition.
      if let leaving = presenting.presentedViewController, leaving.isBeingDismissed,
        attempt < Self.presentAttempts
      {
        pendingSpec = spec
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentRetry) { [weak self] in
          MainActor.assumeIsolated {
            guard let self, let spec = self.pendingSpec else { return }
            self.pendingSpec = nil
            self.present(spec, attempt: attempt + 1)
          }
        }
        return
      }

      let controller = AVPlayerViewController()
      controller.delegate = self
      // Le moteur écrit seul les critères d'affichage, avant d'affecter l'item :
      // tvOS 26.5 refuse sinon les variantes HDR (README AetherEngine, « Host
      // setup on tvOS »).
      controller.appliesPreferredDisplayCriteriaAutomatically = false
      // Le menu Vitesse d'AVKit règle `defaultRate` sans le moteur ni la
      // séance partagée, et double celui d'Onyx : une liste vide le masque.
      controller.speeds = []
      // Onyx ne propose pas l'image dans l'image sur Apple TV, et
      // `PlayerScreen` n'est pas prêt à vivre sans écran.
      controller.allowsPictureInPicturePlayback = false
      controller.player = engine.currentAVPlayer
      // `engine.videoGravity` ne règle que les calques du moteur : celui
      // d'AVKit garde le sien, que le format d'image du menu doit suivre.
      controller.videoGravity = engine.videoGravity
      self.controller = controller
      closingFromHere = false
      userDismissalAnnounced = false
      attachLayers(to: controller)
      apply(spec)
      observe()
      // Une demande permanente : tant que l'écran natif est là, chaque
      // `selectSubtitleTrack` de Dart passe aussi au groupe `legible`, que
      // seul AVKit peint ici (Sodalite#156). Sans elle, la piste choisie ne
      // s'affichait que dans la couche Flutter, qui n'est plus montée.
      engine.setNativeSubtitleRendering(true)

      presenting.present(controller, animated: true) { [weak self, weak controller] in
        MainActor.assumeIsolated {
          guard let self, let controller, self.controller === controller else { return }
          // UIKit ne lève rien quand il refuse une présentation (contrôleur
          // déjà occupé, hors fenêtre) : il journalise et passe.
          if controller.presentingViewController == nil {
            self.teardown()
            self.emit(.unavailable, reason: .presentationFailed)
            return
          }
          // Une question arrivée avec la première spec attendait la fin de
          // la présentation : UIKit n'en accepte pas deux à la fois.
          self.syncPrompt()
        }
      }
    }

    func update(_ spec: OnyxAppleNativeSpec) {
      // Une présentation en attente prendra la spec la plus récente.
      if pendingSpec != nil {
        pendingSpec = spec
        return
      }
      guard controller != nil else { return }
      apply(spec)
    }

    func dismiss() {
      close { [weak self] in self?.emit(.dismissed, reason: .requested) }
    }

    /// Le format d'image choisi dans Dart (`setVideoFit`) : l'image d'AVKit et
    /// les sous-titres image le suivent ensemble.
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
      controller?.videoGravity = gravity
      bitmapSubtitles?.gravity = gravity
    }

    /// Dart vient de commander le lecteur : le débit qui change derrière
    /// n'est pas un geste de la télécommande. [playing] est l'état demandé,
    /// nil pour une commande qui n'en demande pas (recherche, vitesse).
    func noteHostCommand(playing: Bool?) {
      transport.noteHostCommand(playing: playing)
    }

    /// Le lecteur est détruit : Dart n'écoute plus, rien à lui dire.
    func release() {
      close(then: nil)
    }

    // MARK: - Spec

    /// Les couches de `contentOverlayView`, dans l'ordre : les sous-titres
    /// image d'abord, l'annonce par-dessus.
    private func attachLayers(to controller: AVPlayerViewController) {
      let bitmapSubtitles = NativeBitmapSubtitles(engine: engine) { [weak self] in
        self?.fallBackToFlutter(.bitmapSubtitles)
      }
      bitmapSubtitles.gravity = engine.videoGravity
      bitmapSubtitles.attach(to: controller)
      self.bitmapSubtitles = bitmapSubtitles
      let overlay = NativeOverlayView()
      overlay.attach(to: controller)
      self.overlay = overlay

      panels = NativeInfoPanels(
        statsValues: { [weak self] in self?.statsValues() ?? [:] },
        onGesture: { [weak self] panelId, gesture in self?.panelGesture(panelId, gesture) })
      let nextUp = NativeNextUp(
        onPlay: { [weak self] in
          self?.noteActivity()
          self?.emit(.action, actionId: NativeNextUp.playActionId)
        },
        onLater: { [weak self] in
          self?.noteActivity()
          self?.emit(.action, actionId: NativeNextUp.laterActionId)
        })
      controller.contentProposalViewController = nextUp.controller
      self.nextUp = nextUp
    }

    /// Par morceaux : réaffecter les menus ou les panneaux à chaque spec
    /// fermerait un menu ouvert ou ferait perdre le focus, alors que la
    /// plupart des specs ne changent qu'un compte à rebours ou une annonce
    /// (§1.7 de l'inventaire).
    private func apply(_ spec: OnyxAppleNativeSpec) {
      guard let controller else { return }
      let old = self.spec
      self.spec = spec
      if old?.menus != spec.menus || old?.settingsLabel != spec.settingsLabel {
        controller.transportBarCustomMenuItems = settingsMenu(spec)
      }
      if old?.actions != spec.actions {
        controller.contextualActions = spec.actions.map(action)
      }
      // Vide, AVKit n'en montre aucune : son « Lire depuis le début »
      // chercherait sans Dart. L'en-tête en accepte deux au plus.
      if old?.infoActions != spec.infoActions {
        controller.infoViewActions = spec.infoActions.prefix(2).map(action)
      }
      if old?.title != spec.title || old?.subtitle != spec.subtitle || old?.overview != spec.overview
        || old?.posterUrl != spec.posterUrl
      {
        applyMetadata()
        fetchPosterIfNeeded(spec.posterUrl)
      }
      if old?.chapters != spec.chapters {
        engine.currentAVPlayerItem?.navigationMarkerGroups = Self.chapterGroups(spec.chapters)
      }
      panels?.apply(spec.panels, to: controller)
      nextUp?.apply(spec.nextUp, item: engine.currentAVPlayerItem)
      overlay?.toast = spec.toast
      syncPrompt()
    }

    /// Un seul bouton, l'engrenage, qui ouvre les sous-menus. La barre de
    /// transport de tvOS ne montre que les éléments qui ont une image : les
    /// menus posés à plat, sans icône, n'y apparaissaient pas, et Qualité
    /// comme Audio restaient hors d'atteinte.
    private func settingsMenu(_ spec: OnyxAppleNativeSpec) -> [UIMenuElement] {
      guard !spec.menus.isEmpty else { return [] }
      return [
        UIMenu(
          title: spec.settingsLabel, image: UIImage(systemName: "gearshape"),
          children: spec.menus.map(menu))
      ]
    }

    /// Dart reste maître de l'état coché : un choix n'en change rien ici, il
    /// attend la spec suivante. `.singleSelection` ne fait que l'anticiper.
    private func menu(_ menu: OnyxAppleNativeMenu) -> UIMenu {
      let menuId = menu.id
      let children = menu.options.map { option in
        let element = UIAction(title: option.label, state: option.selected ? .on : .off) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.noteActivity()
            self?.emit(.menuSelected, menuId: menuId, optionId: option.id)
          }
        }
        element.subtitle = option.detail
        return element
      }
      let checked = menu.options.contains(where: \.selected)
      let submenu = UIMenu(
        title: menu.label, image: menu.icon.flatMap { UIImage(systemName: $0) },
        options: checked ? .singleSelection : [], children: children)
      // La valeur choisie sous le titre du sous-menu, comme « Qualité ·
      // Auto » dans l'interface Onyx : sans elle, il faudrait ouvrir chaque
      // sous-menu pour savoir où on en est.
      submenu.subtitle = menu.options.first(where: \.selected)?.label
      return submenu
    }

    private func action(_ action: OnyxAppleNativeAction) -> UIAction {
      let actionId = action.id
      return UIAction(title: action.label) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.noteActivity()
          self?.emit(.action, actionId: actionId)
        }
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
          // peut servir du WebP. Hors du fil principal : décoder puis
          // réencoder une affiche y prenait plusieurs images, au moment même
          // où l'écran natif se présente. Un JPEG (`FF D8`) passe tel quel.
          let jpeg = await Task.detached(priority: .utility) { () -> Data? in
            if data.starts(with: [0xFF, 0xD8]) { return data }
            return UIImage(data: data)?.jpegData(compressionQuality: 0.9)
          }.value
          guard let jpeg else { return }
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

    /// Les chapitres forment le premier groupe, sans titre (en-tête
    /// `AVPlayerItem.h`) : ils remplacent ceux que le fichier déclare. Une
    /// liste vide laisse ceux du fichier.
    private static func chapterGroups(_ chapters: [OnyxAppleNativeChapter]) -> [AVNavigationMarkersGroup] {
      guard !chapters.isEmpty else { return [] }
      let markers = chapters.map { chapter in
        let start = CMTime(value: chapter.startMs, timescale: 1000)
        let end = CMTime(value: max(chapter.endMs, chapter.startMs), timescale: 1000)
        return AVTimedMetadataGroup(
          items: [metadata(.commonIdentifierTitle, chapter.title)],
          timeRange: CMTimeRange(start: start, end: end))
      }
      return [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: markers)]
    }

    /// Les mesures du panneau Stats, relues chaque seconde tant qu'il est
    /// visible, avec la fonction qui sert `stats()` à Dart.
    private func statsValues() -> [String: String] {
      guard let stats = stats() else { return [:] }
      return NativeStatsFormat.values(stats, videoFormat: StatusMapping.videoFormat(engine.videoFormat))
    }

    private func panelGesture(_ panelId: String, _ gesture: NativeInfoPanelController.Gesture) {
      noteActivity()
      switch gesture {
      case .row(let rowId): emit(.panelRowSelected, panelId: panelId, rowId: rowId)
      case .tab(let optionId): emit(.panelTabSelected, optionId: optionId, panelId: panelId)
      case .action(let actionId): emit(.action, actionId: actionId)
      }
    }

    // MARK: - Question

    /// La question de Dart, posée par-dessus le lecteur. Elle n'est reprise
    /// que si son `id` change, et retirée quand la spec n'en porte plus.
    private func syncPrompt() {
      guard let controller else { return }
      let wanted = spec?.prompt
      if answeredPrompt != wanted?.id { answeredPrompt = nil }
      if let shown = prompt, shown.id != wanted?.id {
        prompt = nil
        // Une question qui en remplace une autre attend la fin de ce retrait :
        // UIKit n'en présente pas deux à la fois, et aucune spec ne viendrait
        // forcément la reposer ensuite.
        if shown.alert.presentingViewController != nil {
          shown.alert.dismiss(animated: true) { [weak self] in
            MainActor.assumeIsolated { self?.syncPrompt() }
          }
          return
        }
      }
      guard let wanted, prompt == nil, answeredPrompt != wanted.id,
        controller.viewIfLoaded?.window != nil, !controller.isBeingPresented,
        controller.presentedViewController == nil
      else { return }

      let alert = UIAlertController(title: wanted.title, message: wanted.message, preferredStyle: .alert)
      for (index, action) in wanted.actions.enumerated() {
        let actionId = action.id
        // `.cancel` : c'est l'action que déclenche Menu.
        let style: UIAlertAction.Style = actionId == wanted.cancelActionId ? .cancel : .default
        let element = UIAlertAction(title: action.label, style: style) { [weak self] _ in
          MainActor.assumeIsolated { self?.promptAnswered(wanted.id, actionId: actionId) }
        }
        alert.addAction(element)
        if index == 0 { alert.preferredAction = element }
      }
      prompt = (wanted.id, alert)
      controller.present(alert, animated: true)
    }

    private func promptAnswered(_ promptId: String, actionId: String) {
      if prompt?.id == promptId { prompt = nil }
      answeredPrompt = promptId
      noteActivity()
      emit(.action, actionId: actionId)
    }

    // MARK: - Moteur

    /// Les `@Published` émettent la nouvelle valeur *avant* de l'écrire : on
    /// lit donc celle reçue, jamais la propriété du moteur.
    private func observe() {
      subscriptions.removeAll()
      engine.$currentAVPlayer
        .sink { [weak self] player in
          MainActor.assumeIsolated {
            self?.transport.watch(player)
            self?.playerChanged(player)
          }
        }
        .store(in: &subscriptions)
      engine.$videoRoute
        .sink { [weak self] route in
          MainActor.assumeIsolated {
            if route == .software { self?.fallBackToFlutter(.softwareRoute) }
          }
        }
        .store(in: &subscriptions)
      engine.systemCaptionRequest
        .receive(on: DispatchQueue.main)
        .sink { [weak self] request in
          MainActor.assumeIsolated { self?.captionRequested(request) }
        }
        .store(in: &subscriptions)
      engine.$currentAVPlayerItem
        .sink { [weak self] item in
          MainActor.assumeIsolated {
            self?.watchSelection(of: item)
            self?.decorate(item)
          }
        }
        .store(in: &subscriptions)
    }

    /// Le moteur ne rejoue que `externalMetadata` sur l'item neuf d'un
    /// rechargement (spike, Q2) : chapitres et proposition s'y reposent.
    private func decorate(_ item: AVPlayerItem?) {
      guard let item, let spec else { return }
      item.navigationMarkerGroups = Self.chapterGroups(spec.chapters)
      nextUp?.attach(to: item)
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
    /// qui refuse la source, AE#561), ou une piste image arriver sans couche
    /// pour la peindre : Dart reprend l'écran Flutter.
    private func fallBackToFlutter(_ reason: OnyxAppleNativeReason) {
      guard controller != nil, !closingFromHere else { return }
      emit(.unavailable, reason: reason)
      close(then: nil)
    }

    /// AVKit ou les sous-titres automatiques du système ont choisi une piste
    /// alors qu'aucune n'était active : le moteur l'a déjà désélectionnée et
    /// publie la demande (Sodalite#65). Dart décide et rappelle
    /// `selectSubtitleTrack`, que la demande permanente de rendu natif porte
    /// jusqu'au groupe `legible`.
    ///
    /// La demande ne porte que la langue : à langue égale, la piste texte passe
    /// avant l'image, qui ne répond que seule dans sa langue.
    private func captionRequested(_ request: SystemCaptionRequest) {
      guard controller != nil else { return }
      guard
        let track = CaptionLanguage.track(language: request.language, rank: 0, in: engine.subtitleTracks)
          ?? CaptionLanguage.bitmapTrack(language: request.language, in: engine.subtitleTracks)
      else {
        NSLog("Onyx: sous-titre demandé par le système sans piste correspondante (\(request.language ?? "sans langue"))")
        return
      }
      emit(.subtitleSelected, trackId: String(track.id))
    }

    /// Une fois qu'une piste est active, le moteur rend la sélection à l'hôte
    /// et ne publie plus rien : un second choix dans le menu AVKit tiendrait à
    /// l'écran sans que Dart le sache, et la mémoire des pistes se tromperait.
    /// On le lit donc sur l'item.
    private func watchSelection(of item: AVPlayerItem?) {
      stopWatchingSelection()
      guard let item else { return }
      selectionObserver = NotificationCenter.default.addObserver(
        forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: item, queue: .main
      ) { [weak self, weak item] _ in
        MainActor.assumeIsolated {
          guard let self, let item else { return }
          Task { await self.legibleSelectionChanged(on: item) }
        }
      }
    }

    private func stopWatchingSelection() {
      if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
      selectionObserver = nil
      lastLegible = nil
    }

    private func legibleSelectionChanged(on item: AVPlayerItem) async {
      guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
        controller != nil, item === engine.currentAVPlayerItem
      else { return }
      let selected = item.currentMediaSelection.selectedMediaOption(in: group)
      let previous = lastLegible
      lastLegible = selected
      // Sans piste active, c'est l'épingle du moteur qui répond, par
      // `systemCaptionRequest` : ne pas le dire deux fois.
      guard let active = engine.activeSubtitleTrackIndex else { return }
      guard let selected else {
        if previous != nil { emit(.subtitleSelected) }
        return
      }
      // Le moteur qui réaffirme sa propre piste (rechargement, changement
      // d'audio) retombe sur la piste active : rien à dire.
      guard let track = engineTrack(of: selected, in: group), track.id != active else { return }
      emit(.subtitleSelected, trackId: String(track.id))
    }

    /// La piste du moteur derrière une option `legible`. Les renditions OCR
    /// des pistes image se reconnaissent à leur nom (unique, celui que le
    /// moteur a déclaré), à défaut à leur place dans le groupe, qui suit
    /// l'ordre des renditions ; les pistes texte, par langue et par rang.
    private func engineTrack(of option: AVMediaSelectionOption, in group: AVMediaSelectionGroup) -> TrackInfo? {
      let ordinal =
        engine.nativeSubtitleTracks.first(where: { $0.displayName == option.displayName })?.ordinal
        ?? group.options.firstIndex(of: option)
      if let ordinal,
        let bitmap = CaptionLanguage.bitmapTrack(
          nativeOrdinal: ordinal, nativeCount: engine.nativeSubtitleTracks.count,
          isLive: engine.isLive, in: engine.subtitleTracks)
      {
        return bitmap
      }
      let language = CaptionLanguage.normalized(option.extendedLanguageTag)
      let rank = group.options
        .filter { CaptionLanguage.normalized($0.extendedLanguageTag) == language }
        .firstIndex(of: option) ?? 0
      return CaptionLanguage.track(language: option.extendedLanguageTag, rank: rank, in: engine.subtitleTracks)
    }

    // MARK: - Fermeture

    private func close(then completion: (() -> Void)?) {
      pendingSpec = nil
      guard let controller else { return }
      // Menu a déjà lancé la fermeture : en demander une seconde par-dessus
      // ne ferait que perturber la transition, dont la fin fait le ménage.
      if controller.isBeingDismissed {
        completion?()
        return
      }
      closingFromHere = true
      // Depuis celui qui le présente : appelé sur le lecteur, `dismiss` ne
      // fermerait que la question posée par-dessus.
      guard let presenting = controller.presentingViewController else {
        teardown()
        completion?()
        return
      }
      presenting.dismiss(animated: true) { [weak self] in
        MainActor.assumeIsolated {
          self?.teardown()
          completion?()
        }
      }
    }

    private func teardown() {
      if controller != nil {
        // L'interface Flutter reprend : c'est sa couche qui peint, et
        // `AVPlayerLayer` peindrait le groupe `legible` une seconde fois.
        engine.setNativeSubtitleRendering(false)
      }
      stopWatchingSelection()
      subscriptions.removeAll()
      transport.watch(nil)
      bitmapSubtitles?.detach()
      bitmapSubtitles = nil
      overlay?.removeFromSuperview()
      overlay = nil
      panels = nil
      nextUp?.detach()
      nextUp = nil
      prompt = nil
      answeredPrompt = nil
      lastActivity = .distantPast
      userDismissalAnnounced = false
      pendingSpec = nil
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

    /// Menu sur la télécommande, dit à Dart dès le début de la transition :
    /// il enregistre la progression et dépile l'écran du lecteur pendant
    /// qu'AVKit se retire, au lieu de commencer après. Attendre la fin
    /// laissait un écran noir entre le lecteur et la fiche, le temps de la
    /// requête au serveur puis de l'animation de retour.
    func playerViewControllerWillBeginDismissalTransition(_ playerViewController: AVPlayerViewController) {
      guard playerViewController === controller, !closingFromHere, !userDismissalAnnounced else { return }
      userDismissalAnnounced = true
      emit(.dismissed, reason: .userDismissed)
    }

    /// La fin de la transition : le ménage, et le focus rendu à Flutter (une
    /// à trois secondes de focus vide, mesuré dans le spike, quand rien ne le
    /// redemandait).
    func playerViewControllerDidEndDismissalTransition(_ playerViewController: AVPlayerViewController) {
      guard playerViewController === controller, !closingFromHere else { return }
      let announced = userDismissalAnnounced
      teardown()
      if !announced { emit(.dismissed, reason: .userDismissed) }
      if let host = Self.presentingController() {
        host.setNeedsFocusUpdate()
        host.updateFocusIfNeeded()
      }
    }

    /// Saut de 10 s, balayage, chapitre : une seule fois par navigation,
    /// avant la reprise. Avec `interceptSeeks` (HLS, où une recherche peut
    /// reconstruire la session), la lecture reste où elle était et Dart
    /// cherche lui-même.
    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      timeToSeekAfterUserNavigatedFrom oldTime: CMTime, to targetTime: CMTime
    ) -> CMTime {
      noteActivity()
      guard spec?.interceptSeeks == true else { return targetTime }
      emit(.seekRequested, positionMs: Self.milliseconds(targetTime))
      return oldTime
    }

    /// La navigation déjà appliquée par AVKit, que Dart annonce à la séance.
    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      willResumePlaybackAfterUserNavigatedFrom oldTime: CMTime, to targetTime: CMTime
    ) {
      guard spec?.interceptSeeks != true else { return }
      emit(
        .userSeeked, positionMs: Self.milliseconds(targetTime),
        fromPositionMs: Self.milliseconds(oldTime))
    }

    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      willTransitionToVisibilityOfTransportBar visible: Bool,
      with coordinator: any AVPlayerViewControllerAnimationCoordinator
    ) {
      if visible { noteActivity() }
    }

    func playerViewController(
      _ playerViewController: AVPlayerViewController, shouldPresent proposal: AVContentProposal
    ) -> Bool {
      nextUp?.shouldPresent(proposal) ?? false
    }

    func playerViewController(
      _ playerViewController: AVPlayerViewController, didAccept proposal: AVContentProposal
    ) {
      nextUp?.accepted(proposal)
    }

    /// Implémenté pour qu'AVKit ne ferme pas le lecteur (en-tête) : un refus
    /// vaut « Plus tard », Dart garde la main sur la suite.
    func playerViewController(
      _ playerViewController: AVPlayerViewController, didReject proposal: AVContentProposal
    ) {
      nextUp?.deferred(proposal)
    }

    // MARK: - Événements

    /// Quelqu'un se sert de la télécommande : « Vous regardez encore ? » et
    /// les comptes à rebours de Dart s'en servent. Une fois toutes les 5 s au
    /// plus, ce qui suffit à ces deux usages.
    private func noteActivity() {
      let now = Date()
      guard now.timeIntervalSince(lastActivity) >= 5 else { return }
      lastActivity = now
      emit(.userActivity)
    }

    private func emit(
      _ kind: OnyxAppleNativeEventKind,
      actionId: String? = nil, menuId: String? = nil, optionId: String? = nil,
      trackId: String? = nil, reason: OnyxAppleNativeReason? = nil,
      playing: Bool? = nil, positionMs: Int64? = nil, fromPositionMs: Int64? = nil,
      panelId: String? = nil, rowId: String? = nil
    ) {
      send(
        OnyxAppleNativeEvent(
          playerId: playerId, kind: kind, actionId: actionId, menuId: menuId,
          optionId: optionId, trackId: trackId, reason: reason, playing: playing,
          positionMs: positionMs, fromPositionMs: fromPositionMs, panelId: panelId, rowId: rowId))
    }

    private static func milliseconds(_ time: CMTime) -> Int64 {
      time.isNumeric ? StatusMapping.milliseconds(time.seconds) : 0
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

  /// Lecture et pause décidées dans AVKit (bouton central, Centre de
  /// contrôle, app Remote de l'iPhone) : elles vont droit à l'`AVPlayer`,
  /// sans passer par Dart, qui doit pourtant les annoncer à la séance
  /// partagée (§1.1 de l'inventaire de parité).
  ///
  /// Le débit change aussi pour d'autres raisons, qu'il faut taire : une
  /// commande de Dart (la marque de `PlayerHost`), le rechargement d'un item
  /// (le moteur met en pause avant de remplacer l'item, puis relance à
  /// `readyToPlay`), l'attente du tampon, la fin de l'item. L'état est relu
  /// après un court délai, pour qu'une rafale de changements n'en fasse qu'un.
  @MainActor
  final class NativeTransportWatch {
    /// Le temps qu'une commande de Dart met à se voir sur l'`AVPlayer`. Il se
    /// prolonge tant que l'item charge ou que le tampon se remplit.
    private static let hostWindow: TimeInterval = 2
    private static let settle: TimeInterval = 0.4

    private let onChange: (_ playing: Bool, _ positionMs: Int64) -> Void
    private weak var player: AVPlayer?
    private var rateObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var reported: Bool?
    private var hostCommand: (playing: Bool?, deadline: Date)?
    private var generation = 0

    init(onChange: @escaping (_ playing: Bool, _ positionMs: Int64) -> Void) {
      self.onChange = onChange
    }

    func watch(_ player: AVPlayer?) {
      if let player, player === self.player, rateObserver != nil { return }
      if let rateObserver { NotificationCenter.default.removeObserver(rateObserver) }
      rateObserver = nil
      statusObservation = nil
      generation += 1
      self.player = player
      guard let player else {
        reported = nil
        return
      }
      reported = player.rate != 0
      rateObserver = NotificationCenter.default.addObserver(
        forName: AVPlayer.rateDidChangeNotification, object: player, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.scheduleCheck() }
      }
      statusObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
        DispatchQueue.main.async { [weak self] in
          MainActor.assumeIsolated { self?.scheduleCheck() }
        }
      }
    }

    func noteHostCommand(playing: Bool?) {
      hostCommand = (playing, Date().addingTimeInterval(Self.hostWindow))
    }

    private func scheduleCheck() {
      generation += 1
      let expected = generation
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
        MainActor.assumeIsolated {
          guard let self, self.generation == expected else { return }
          self.check()
        }
      }
    }

    private func check() {
      guard let player else { return }
      // Un item qui charge, ou un tampon qui se remplit, garde le débit
      // demandé : rien n'est encore décidé, la commande de Dart reste armée.
      guard let item = player.currentItem, item.status == .readyToPlay,
        player.timeControlStatus != .waitingToPlayAtSpecifiedRate
      else {
        if let command = hostCommand {
          hostCommand = (command.playing, Date().addingTimeInterval(Self.hostWindow))
        }
        return
      }
      let playing = player.rate != 0
      if let command = hostCommand {
        if Date() > command.deadline {
          hostCommand = nil
        } else if command.playing == nil || command.playing == playing {
          if command.playing != nil { hostCommand = nil }
          reported = playing
          return
        }
      }
      guard playing != reported else { return }
      reported = playing
      let position = item.currentTime().seconds
      let duration = item.duration.seconds
      // La fin de l'item arrête le débit : c'est l'épisode qui finit.
      if !playing, duration.isFinite, position.isFinite, position >= duration - 1 { return }
      onChange(playing, position.isFinite ? StatusMapping.milliseconds(position) : 0)
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

    /// La piste texte de [language] au rang [rank] parmi celles de la même
    /// langue, dans l'ordre du moteur : c'est l'ordre des options `legible`,
    /// que le moteur rapproche lui aussi par langue et par rang. Les pistes
    /// image sont sautées : leurs options passent par `bitmapTrack`.
    static func track(language: String?, rank: Int, in tracks: [TrackInfo]) -> TrackInfo? {
      let wanted = normalized(language)
      let candidates = tracks.filter {
        !StatusMapping.bitmapSubtitleCodecs.contains($0.codec) && normalized($0.language) == wanted
      }
      return rank < candidates.count ? candidates[rank] : candidates.first
    }

    /// La piste image derrière la rendition native [nativeOrdinal]. Le moteur
    /// ajoute une rendition OCR par piste image (hors direct), après toutes les
    /// autres et dans l'ordre de ses pistes : les dernières renditions sont
    /// donc les pistes image, dans le même ordre.
    static func bitmapTrack(nativeOrdinal: Int, nativeCount: Int, isLive: Bool, in tracks: [TrackInfo])
      -> TrackInfo?
    {
      guard !isLive else { return nil }
      let bitmaps = tracks.filter { StatusMapping.bitmapSubtitleCodecs.contains($0.codec) }
      let first = nativeCount - bitmaps.count
      guard first >= 0, nativeOrdinal >= first, nativeOrdinal < nativeCount else { return nil }
      return bitmaps[nativeOrdinal - first]
    }

    /// La première piste image de [language].
    static func bitmapTrack(language: String?, in tracks: [TrackInfo]) -> TrackInfo? {
      let wanted = normalized(language)
      return tracks.first {
        StatusMapping.bitmapSubtitleCodecs.contains($0.codec) && normalized($0.language) == wanted
      }
    }

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
