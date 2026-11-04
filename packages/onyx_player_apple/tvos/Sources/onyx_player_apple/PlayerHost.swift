import AVFoundation
import Foundation

/// Les lecteurs vivants, et le contrat Pigeon qui les pilote.
///
/// Pigeon appelle ces méthodes sur le thread principal, mais son protocole
/// n'est pas isolé sur `MainActor`, alors qu'AetherEngine l'est entièrement.
/// Chaque appel passe donc par `onMain`, qui le vérifie au lieu de le supposer :
/// un appel venu d'ailleurs s'arrête net plutôt que de courir sur le moteur.
final class PlayerHost: NSObject, OnyxApplePlayerApi {
  let statuses = StatusStream()
  let subtitles = SubtitleStream()
  let pictureInPicture = PictureInPictureStream()
  let engineLog = EngineLogRelay()
  let nativeEvents = NativeEventStream()

  private var players: [Int64: AetherPlayer] = [:]
  private var nextId: Int64 = 1
  #if os(tvOS)
    private var presenters: [Int64: NativePlayerPresenter] = [:]
  #endif

  /// Le lecteur auquel une vue se rattache. Nil s'il a déjà été détruit : la
  /// vue reste noire plutôt que de faire tomber l'app.
  func player(_ id: Int64) -> AetherPlayer? {
    players[id]
  }

  private func onMain<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
    try MainActor.assumeIsolated(body)
  }

  private func require(_ id: Int64) throws -> AetherPlayer {
    guard let player = players[id] else {
      throw PigeonError(code: "unknown_player", message: "Lecteur \(id) inconnu ou détruit", details: nil)
    }
    return player
  }

  // MARK: - OnyxApplePlayerApi

  func create() throws -> Int64 {
    try onMain {
      let id = nextId
      nextId += 1
      let statuses = self.statuses
      let subtitles = self.subtitles
      let pictureInPicture = self.pictureInPicture
      players[id] = try AetherPlayer(
        id: id,
        onStatus: { statuses.send($0) },
        onSubtitles: { subtitles.send($0) },
        onPictureInPicture: { pictureInPicture.send($0) })
      return id
    }
  }

  func release(playerId: Int64) throws {
    onMain {
      #if os(tvOS)
        presenters.removeValue(forKey: playerId)?.release()
      #endif
      players.removeValue(forKey: playerId)?.release()
    }
  }

  func open(playerId: Int64, url: String, startPositionMs: Int64, play: Bool) throws {
    try onMain { try require(playerId).open(url, startMs: startPositionMs, play: play) }
  }

  func play(playerId: Int64) throws {
    try onMain { try require(playerId).play() }
  }

  func pause(playerId: Int64) throws {
    try onMain { try require(playerId).pause() }
  }

  func seekTo(playerId: Int64, positionMs: Int64) throws {
    try onMain { try require(playerId).seek(toMs: positionMs) }
  }

  func stop(playerId: Int64) throws {
    try onMain { try require(playerId).stop() }
  }

  func setVolume(playerId: Int64, volume: Double) throws {
    try onMain { try require(playerId).engine.volume = Float(volume) }
  }

  func setRate(playerId: Int64, rate: Double) throws {
    try onMain { try require(playerId).engine.setRate(Float(rate)) }
  }

  func setVideoFit(playerId: Int64, fit: OnyxAppleVideoFit) throws {
    let gravity: AVLayerVideoGravity = fit == .cover ? .resizeAspectFill : .resizeAspect
    try onMain { try require(playerId).engine.videoGravity = gravity }
  }

  func setPreferredAudioLanguages(playerId: Int64, priorities: [String]) throws {
    try onMain { try require(playerId).preferredAudioLanguages = priorities }
  }

  func setLoadSubtitles(playerId: Int64, subtitles: OnyxAppleLoadSubtitles) throws {
    try onMain { try require(playerId).loadSubtitles = subtitles }
  }

  func selectAudioTrack(playerId: Int64, trackId: String) throws {
    try onMain { try require(playerId).selectAudioTrack(trackId) }
  }

  func selectSubtitleTrack(playerId: Int64, trackId: String?) throws {
    try onMain { try require(playerId).selectSubtitleTrack(trackId) }
  }

  func setExternalSubtitle(playerId: Int64, vttContent: String?, language: String?, title: String?) throws {
    try onMain {
      try require(playerId).setExternalSubtitle(vttContent, language: language, title: title)
    }
  }

  func status(playerId: Int64) throws -> OnyxApplePlayerStatus {
    try onMain { try require(playerId).snapshot() }
  }

  func stats(playerId: Int64) throws -> OnyxApplePlaybackStats {
    try onMain { try require(playerId).stats() }
  }

  func supportsPictureInPicture() throws -> Bool {
    onMain { PictureInPictureBridge.isSupported }
  }

  func setPictureInPictureArmed(playerId: Int64, armed: Bool) throws {
    try onMain { try require(playerId).setPictureInPictureArmed(armed) }
  }

  // Le lecteur natif n'existe que sur l'Apple TV. Ailleurs, et pour un
  // lecteur inconnu, la réponse est un `unavailable`, jamais une erreur : Dart
  // garde alors l'écran Flutter au lieu de rester sur un appel en échec.
  func presentNative(playerId: Int64, spec: OnyxAppleNativeSpec) throws {
    #if os(tvOS)
      onMain {
        guard let presenter = presenter(playerId) else {
          nativeEvents.send(
            OnyxAppleNativeEvent(
              playerId: playerId, kind: .unavailable, reason: .presentationFailed))
          return
        }
        presenter.present(spec)
      }
    #else
      nativeEvents.send(
        OnyxAppleNativeEvent(
          playerId: playerId, kind: .unavailable, reason: .unsupported))
    #endif
  }

  func updateNative(playerId: Int64, spec: OnyxAppleNativeSpec) throws {
    #if os(tvOS)
      onMain { presenters[playerId]?.update(spec) }
    #endif
  }

  func dismissNative(playerId: Int64) throws {
    #if os(tvOS)
      onMain { presenters[playerId]?.dismiss() }
    #endif
  }

  #if os(tvOS)
    /// Créé au premier `presentNative`, et gardé avec son lecteur : l'affiche
    /// téléchargée sert encore à l'épisode suivant s'il la partage.
    @MainActor private func presenter(_ id: Int64) -> NativePlayerPresenter? {
      if let presenter = presenters[id] { return presenter }
      guard let player = players[id] else { return nil }
      let events = nativeEvents
      let presenter = NativePlayerPresenter(
        playerId: id, engine: player.engine, send: { events.send($0) })
      presenters[id] = presenter
      return presenter
    }
  #endif
}
