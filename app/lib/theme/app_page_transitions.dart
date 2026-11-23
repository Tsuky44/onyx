// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../navigation/search_route_observer.dart';
import 'app_motion.dart';

/// La transition de page d'Onyx : la page arrive en fondu en montant de
/// quelques pixels, et repart de même.
///
/// Sans elle, chaque `MaterialPageRoute` prenait celle de son système : un
/// zoom sous Windows et Android, un glissé latéral sous macOS — la même fiche
/// ne s'ouvrait pas de la même façon selon l'ordinateur, et le zoom d'Android
/// (450 ms) sortait du contrat de mouvement (`PROJECT_DESIGN.md` §10,
/// 180–280 ms).
///
/// iOS garde le glissé de [CupertinoPageTransitionsBuilder] : il porte le geste
/// de retour depuis le bord de l'écran, que tout utilisateur d'iPhone fait
/// sans y penser.
///
/// Sur le web (CanvasKit), une opacité animée sur une page entière force un
/// `saveLayer` plein écran à chaque image, flous du verre compris : le pire
/// cas pour le rendu, la fiche qui « rame » à l'ouverture. La page y arrive
/// donc opaque, par un glissé seul, sans aucune opacité animée (ADR-0149).
/// Le lecteur garde son fondu : jamais de géométrie, et il n'a pas de verre.
class OnyxPageTransitionsBuilder extends PageTransitionsBuilder {
  const OnyxPageTransitionsBuilder({this.cheap = kIsWeb});

  /// Transition sans opacité animée sur la page (web, webOS compris).
  final bool cheap;

  /// La montée, en fraction de la hauteur : une vingtaine de pixels sur un
  /// téléphone, assez pour donner une direction, trop peu pour « glisser ».
  static const double rise = 0.025;

  @override
  Duration get transitionDuration => AppMotion.emphasis;

  /// Le retour est plus vif que l'aller : on quitte une page qu'on connaît.
  @override
  Duration get reverseTransitionDuration => AppMotion.standard;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: AppMotion.curve.flipped,
    );
    final isPlayer = route.settings.name == SearchRouteObserver.playerRouteName;
    if (cheap && !isPlayer) {
      // Sous « réduire les animations », la page apparaît d'un coup.
      if (AppMotion.reduced(context)) return child;
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, rise),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    }
    final faded = FadeTransition(opacity: curved, child: child);
    // Le lecteur ne subit jamais de transformation : sa vidéo est une surface
    // native sur Android, que Flutter ne sait pas déplacer. Un fondu seul. Et
    // sous « réduire les animations », le fondu reste, la montée disparaît
    // ([AppMotion.move]).
    if (isPlayer || AppMotion.reduced(context)) {
      return faded;
    }
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, rise),
        end: Offset.zero,
      ).animate(curved),
      child: faded,
    );
  }
}

/// Le thème des transitions de l'app, par plateforme. Sur le web, la
/// `TargetPlatform` est celle du système du navigateur : toutes les entrées
/// prennent la transition d'Onyx, y compris iOS (pas de geste de bord dans un
/// navigateur, et le glissé de Cupertino peint une ombre sur toute la page).
final PageTransitionsTheme appPageTransitionsTheme = PageTransitionsTheme(
  builders: kIsWeb
      ? <TargetPlatform, PageTransitionsBuilder>{
          for (final platform in TargetPlatform.values)
            platform: const OnyxPageTransitionsBuilder(),
        }
      : const <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: OnyxPageTransitionsBuilder(),
          TargetPlatform.fuchsia: OnyxPageTransitionsBuilder(),
          TargetPlatform.linux: OnyxPageTransitionsBuilder(),
          TargetPlatform.macOS: OnyxPageTransitionsBuilder(),
          TargetPlatform.windows: OnyxPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
);
