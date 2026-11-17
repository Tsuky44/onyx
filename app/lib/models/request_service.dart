/// Le compagnon de demandes branché sur un serveur (ADR-0136) : celui qui
/// reçoit les demandes et les fait télécharger. Le serveur parle à chacun dans
/// sa langue ; l'app n'en retient que le nom à montrer et ce que l'écran de
/// réglages change de l'un à l'autre.
enum RequestService {
  mediaHub('mediahub', 'MediaHub', 'http://192.168.1.10:4400'),
  overseerr('overseerr', 'Overseerr', 'http://192.168.1.10:5055'),
  jellyseerr('jellyseerr', 'Jellyseerr', 'http://192.168.1.10:5055');

  const RequestService(this.wire, this.label, this.urlExample);

  /// La valeur de `request_service` dans les réglages du serveur.
  final String wire;

  /// Un nom propre : il ne se traduit pas.
  final String label;

  /// Une adresse d'exemple, au port par défaut du service.
  final String urlExample;

  /// Overseerr et Jellyseerr partagent une API et leurs règles : une clé API
  /// d'administrateur, et pas de compte créé pour Onyx.
  bool get isSeerr => this != mediaHub;

  /// Une valeur inconnue, « onyxhub », ou un serveur d'avant le choix du
  /// service (rien) : MediaHub, le seul compagnon qu'il connaît.
  static RequestService parse(String? raw) => RequestService.values.firstWhere(
        (service) => service.wire == raw,
        orElse: () => RequestService.mediaHub,
      );
}
