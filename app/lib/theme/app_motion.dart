import 'package:flutter/material.dart';

import 'lite_mode.dart';

/// Motion tokens — the single place that decides how long anything in the app
/// takes to move, and how it behaves when the user asked the system for less
/// motion.
///
/// **Durations stay inside 180–280 ms.** That range is the contract
/// (`PROJECT_DESIGN.md` §10: "Motion: 180–280ms ease-out"), not a preference.
/// Adding a value outside it here means the contract changed first.
///
/// **There is no spring in this file, on purpose.** A spring only earns its
/// place where a gesture carries a velocity worth handing off — a drag release,
/// a flick. Nothing in the app does that yet, and Flutter's implicit animations
/// already retarget from the value currently on screen, which is what makes an
/// animation interruptible. The first real candidate is the scrubber, if it
/// ever snaps to chapters on a flick. When that happens the parameters are
/// derived, not guessed: pick a damping ratio and a response (in seconds), then
/// `SpringDescription.withDampingRatio(mass: 1, stiffness: m * pow(2 * pi / response, 2), ratio: damping)`.
abstract final class AppMotion {
  /// Micro-states: hover, selection, a chip changing shape.
  static const Duration micro = Duration(milliseconds: 180);

  /// Le zoom du focus télécommande. Sous la plage 180–280 ms parce qu'il suit
  /// la répétition des flèches : un focus qui finit de grossir après que le
  /// suivant est parti traîne derrière la télécommande.
  static const Duration focus = Duration(milliseconds: 160);

  /// The default. Chrome fades, appearances, disappearances.
  static const Duration standard = Duration(milliseconds: 200);

  /// Large surfaces — sheets, panels — which read as slower at the same speed.
  static const Duration emphasis = Duration(milliseconds: 260);

  /// Un défilement qui suit une entrée continue — flèche maintenue, élan du
  /// trackpad de l'Apple TV. Hors de la plage 180–280 ms parce que ce n'est
  /// pas une transition : chaque pas relance le défilement, qui doit avoir
  /// fini avant le suivant (`TvKeyRepeat.repeatInterval`, 110 ms), sans quoi
  /// le focus court devant une rangée pas encore construite.
  static const Duration track = Duration(milliseconds: 90);

  /// Une dérive lente qui anime une image fixe — le zoom de l'aperçu au survol
  /// d'une carte « Reprendre ». Hors de la plage 180–280 ms parce que ce n'est
  /// pas une transition : rien n'attend qu'elle finisse, elle donne seulement
  /// de la vie à une suite d'images. Toujours passée par [move], donc nulle
  /// sous « réduire les animations ».
  static const Duration ambient = Duration(milliseconds: 2600);

  /// L'écart entre deux cartes d'une arrivée en cascade
  /// (`StaggeredEntranceScope`). Un décalage de départ, pas une durée :
  /// chaque carte dure [emphasis]. 35 ms, comme la cascade d'OnyxHub : assez
  /// pour lire l'ordre, trop peu pour qu'on attende la dernière.
  static const Duration stagger = Duration(milliseconds: 35);

  /// Le faisceau qui traverse une fois un badge « Disponible ». Hors de la
  /// plage 180–280 ms parce que ce n'est pas une transition : rien n'attend
  /// qu'il finisse, il signale seulement l'état en passant. Toujours passé par
  /// [move], donc absent sous « réduire les animations » et en mode léger.
  static const Duration sweep = Duration(milliseconds: 900);

  /// L'ouverture d'une page entière par-dessus celle qu'on regarde — la vue
  /// de recherche qui s'ouvre à la frappe (`SearchResultsRoute`). Hors de la
  /// plage 180–280 ms : à [emphasis], tout l'écran changeait en moins de
  /// 200 ms et l'ouverture se lisait comme une coupure. Ce n'est pas une
  /// attente — la frappe continue dans la barre pendant qu'elle joue.
  static const Duration reveal = Duration(milliseconds: 380);

  /// Le retournement d'une affiche qui montre son menu au dos
  /// (`showPosterFlipMenu`). Hors de la plage 180–280 ms : une rotation d'un
  /// demi-tour à [emphasis] faisait défiler le profil de la carte en trois
  /// images, et l'œil lisait une coupure plutôt qu'un objet qui tourne. Le
  /// menu est focalisable dès l'ouverture : la télécommande n'attend pas la
  /// fin du geste. Passé par [move] pour la rotation ; sous « réduire les
  /// animations », les deux faces se fondent l'une dans l'autre.
  static const Duration flip = Duration(milliseconds: 420);

  /// Le défilement d'une fiche de téléviseur d'une section à l'autre
  /// (`TvSectionsScroll`, ADR-0128) : de « Lecture » à la distribution, la
  /// page parcourt plus d'un demi-écran. Hors de la plage 180–280 ms : à
  /// [standard], l'écran entier changeait dans le temps d'un pas d'affiche
  /// (retour d'essai sur Apple TV : « un peu rapide »). C'est la durée du
  /// trajet le plus long ; un pas dans une liste garde une durée proche de
  /// [standard]. Passé par [move] : nul sous « réduire les animations ».
  static const Duration section = Duration(milliseconds: 460);

  /// La courbe du défilement d'une fiche ([section]). Comme le fondu d'une
  /// page entière ([revealFade]) : un ease-out lance tout l'écran à pleine
  /// vitesse dès la première image. La page part et se pose en douceur.
  static const Curve sectionCurve = Curves.easeInOut;

  /// La courbe du retournement ([flip]). Un ease-out pur lançait l'affiche à
  /// pleine vitesse dès la première image, comme arrachée : la rotation
  /// démarre en douceur et se pose, comme une carte qu'on retourne à la main.
  static const Curve flipCurve = Curves.easeInOutCubic;

  /// La courbe du fondu d'une page entière ([reveal]), seule exception à
  /// [curve]. Un ease-out met l'essentiel du fondu dans les premières images :
  /// sur une petite carte c'est vif, sur tout l'écran c'est brusque. Le fondu
  /// part et finit en douceur ; le mouvement, lui, garde [curve].
  static const Curve revealFade = Curves.easeInOut;

  /// The app's curve (`PROJECT_DESIGN.md` §10: "ease-out"), sauf le fondu
  /// d'une page entière ([revealFade]).
  static const Curve curve = Curves.easeOut;

  /// Press-down scale for interactive cards. Deliberately restrained:
  /// `PROJECT_DESIGN.md` §4 lists the incumbent brief's aggressive 1.1
  /// scale-on-focus as non-transferable.
  static const double pressScale = 0.97;

  /// Whether the platform asked for reduced motion — "Reduce Motion" on
  /// macOS/iOS, "Remove animations" on Android.
  ///
  /// Le mode léger (ADR-0086) pose la même question : un mouvement
  /// géométrique redessine tout ce qu'il traverse à chaque image, et c'est ce
  /// qu'une Apple TV HD ne tient pas. Les fondus restent, comme sous
  /// « réduire les animations ».
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) || LiteScope.of(context);

  /// Duration for an opacity or colour animation.
  ///
  /// Survives reduced motion by design: a cross-fade is not vestibular, and
  /// removing it makes the interface harder to follow rather than calmer.
  /// Takes the context it does not read so that every call site asks the same
  /// question — `fade` or `move` — instead of having to remember which of the
  /// two cares about the setting.
  static Duration fade(BuildContext context, [Duration duration = standard]) =>
      duration;

  /// Duration for a position, size or scale animation — anything geometric.
  ///
  /// Collapses to zero under reduced motion, so the widget lands on its target
  /// state directly instead of travelling there.
  static Duration move(BuildContext context, [Duration duration = standard]) =>
      reduced(context) ? Duration.zero : duration;
}
