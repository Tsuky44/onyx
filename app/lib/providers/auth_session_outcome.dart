part of 'auth_provider.dart';

/// Ce que donne une tentative d'ouverture de session sur le compte actif.
///
/// Quatre issues et pas deux, parce que l'app n'en tire pas la même
/// conclusion : un refus renvoie à l'écran de connexion, un serveur muet peut
/// valoir une bascule, et un serveur qui répond de travers ne prouve pas
/// qu'il est éteint.
enum _SessionOutcome {
  /// Le profil est arrivé : la session est ouverte pour de bon.
  opened,

  /// 401 : la session n'existe plus de l'autre côté.
  unauthorized,

  /// Aucune réponse : le serveur est injoignable d'ici.
  unreachable,

  /// Une réponse, mais inexploitable — un 500, un corps illisible.
  faulted,
}
