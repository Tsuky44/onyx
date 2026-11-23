import AVFoundation
import AetherEngine
import CoreMedia

/// Fait démarrer un film dès que le premier segment est en mémoire.
///
/// AVPlayer ne lance la lecture qu'avec environ deux segments de 4 s d'avance
/// (`AVPlayerWaitingToMinimizeStallsReason`). Sur un remux 4K, c'est ~40 Mo
/// avant la première image en mouvement : mesuré 6,0 s de démarrage, dont
/// 2,2 s passées à attendre le second segment avec 3,5 s déjà en réserve.
/// mpv démarrait, lui, sur quelques Mo.
///
/// AetherEngine coupe court à cette attente pour le direct (`AE#440`,
/// `liveJoinStartsImmediately`), pas pour un film. On applique ici la même
/// règle, une seule fois par ouverture et avec les mêmes gardes :
/// `playImmediately` seulement sur un tampon non vide et assez profond. Sur un
/// tampon vide, AVPlayer le traite comme une panne et reste à l'arrêt ; c'est
/// l'échec qu'AetherEngine a mesuré en coupant l'attente pour de bon. Passé le
/// démarrage, un rechargement en cours de lecture garde la règle d'AVPlayer.
@MainActor
final class FastStart {
  /// Au-dessous d'un segment, le coussin est un fragment et la lecture
  /// repartirait en attente aussitôt. 2 s laisse une marge sur le 1,5 s
  /// d'AetherEngine, calibré pour un direct servi en temps réel : un fichier
  /// arrive en général plus vite que sa lecture, et la réserve grossit.
  static let minimumBufferAhead: Double = 2.0
  /// Une réserve qui se remplit au moins deux fois plus vite qu'elle ne se lit
  /// ne peut pas se vider : la moitié suffit alors pour partir. Sur une ligne
  /// qui porte juste le débit du film, la seconde suivante coûte une seconde
  /// d'écran noir de plus, pour une marge dont cette ligne-là n'a pas besoin.
  static let minimumGrowingBufferAhead: Double = 1.0
  static let minimumFillRate: Double = 2.0
  /// La mesure du remplissage ne vaut rien sur moins que ça : les fragments
  /// arrivent par paquets d'une demi-seconde de film.
  private static let minimumFillSample: TimeInterval = 0.2
  /// Un démarrage qui n'a pas eu lieu dans ce délai n'attend plus sa réserve :
  /// il est en panne, et ce n'est pas à ce raccourci de s'en mêler.
  private static let window: Duration = .seconds(20)
  /// 50 ms et non 150 : le seuil franchi, chaque tour d'attente est du noir à
  /// l'écran, et relire trois propriétés d'AVPlayer ne coûte rien, même à la
  /// puce d'une Apple TV HD.
  private static let pollInterval: Duration = .milliseconds(50)

  private var task: Task<Void, Never>?

  /// À appeler à chaque ouverture. [wantsPlay] est relu à chaque tour : une
  /// pause demandée pendant le démarrage désarme le raccourci.
  func arm(engine: AetherEngine, wantsPlay: @escaping @MainActor () -> Bool) {
    cancel()
    // Le lecteur peut être réutilisé d'une ouverture à l'autre : l'élément en
    // cours avant celle-ci ne dit rien du démarrage qui vient.
    let previousItem = engine.currentAVPlayerItem
    task = Task { @MainActor in
      let deadline = ContinuousClock.now + Self.window
      // Le premier relevé d'une réserve non vide : de quoi mesurer à quelle
      // vitesse elle grossit.
      var firstSample: (at: TimeInterval, ahead: Double)?
      while !Task.isCancelled, ContinuousClock.now < deadline {
        try? await Task.sleep(for: Self.pollInterval)
        guard let player = engine.currentAVPlayer,
              let item = player.currentItem,
              item !== previousItem
        else { continue }
        switch player.timeControlStatus {
        case .playing:
          return
        case .paused:
          continue
        case .waitingToPlayAtSpecifiedRate:
          guard wantsPlay(),
                player.reasonForWaitingToPlay == .toMinimizeStalls,
                !item.isPlaybackBufferEmpty
          else { continue }
          let ahead = Self.bufferedAhead(of: item)
          let now = ProcessInfo.processInfo.systemUptime
          var fillRate: Double?
          if let first = firstSample {
            let elapsed = now - first.at
            if elapsed >= Self.minimumFillSample { fillRate = (ahead - first.ahead) / elapsed }
          } else if ahead > 0 {
            firstSample = (now, ahead)
          }
          guard Self.isEnough(ahead: ahead, fillRate: fillRate) else { continue }
          EngineLog.emit(
            "[Onyx] démarrage sans attendre le second segment (réserve "
              + String(format: "%.2f", ahead) + " s, remplissage "
              + (fillRate.map { String(format: "%.1f", $0) + "x" } ?? "inconnu") + ")")
          player.playImmediately(atRate: player.defaultRate > 0 ? player.defaultRate : 1)
          return
        @unknown default:
          return
        }
      }
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  /// Si la réserve [ahead] (secondes) suffit pour partir. [fillRate] est ce
  /// qu'elle gagne par seconde d'horloge pendant l'attente, où la lecture ne
  /// la consomme pas ; nil tant qu'il n'est pas mesuré.
  static func isEnough(ahead: Double, fillRate: Double?) -> Bool {
    if ahead >= minimumBufferAhead { return true }
    guard let fillRate, fillRate >= minimumFillRate else { return false }
    return ahead >= minimumGrowingBufferAhead
  }

  /// Secondes contiguës en mémoire devant la position de lecture. Le premier
  /// segment commence souvent un peu après la position demandée (le moteur le
  /// cale sur l'image clé) : une plage qui démarre à moins d'une demi-seconde
  /// devant compte.
  static func bufferedAhead(of item: AVPlayerItem) -> Double {
    let now = item.currentTime()
    guard now.isValid, now.isNumeric else { return 0 }
    let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
    for value in item.loadedTimeRanges {
      let range = value.timeRangeValue
      guard range.start <= now + tolerance, range.end > now else { continue }
      let ahead = (range.end - now).seconds
      return ahead.isFinite ? ahead : 0
    }
    return 0
  }
}
