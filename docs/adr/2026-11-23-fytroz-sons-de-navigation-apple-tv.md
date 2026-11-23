# ADR 2026-11-23-fytroz : sur l'Apple TV, Onyx rejoue lui-même les sons de navigation du système

- **Statut :** accepté, **jamais écouté**. Demandé par l'utilisateur (2026-11-23) : « Rajoute le son
  d'Apple quand on navigue dans les menus. » Écrit sans Xcode ni Apple TV : le Swift n'a été ni
  compilé ni exécuté, et aucun son n'est sorti d'un appareil. Le *quand* est couvert par des tests
  Dart ; le *si ça sonne* ne se vérifie que sur une vraie Apple TV (liste « À écouter »).
- **Date :** 2026-11-23
- **Portée :** `app/tvos/Runner/NavigationSound.swift` (nouveau), `AppDelegate.swift`,
  `Runner.xcodeproj/project.pbxproj`, `app/lib/tv/tv_navigation_sound.dart` (nouveau),
  `app/lib/tv/tv_touchpad.dart` (deux annonces), `app/lib/main.dart`,
  `screens/settings/widgets/navigation_sound_tile.dart` (nouveau), `pages/device_page.dart`,
  `settings_search.dart`, `l10n/en.dart`, `test/tv_navigation_sound_test.dart`,
  `test/tv_navigation_sound_host_test.dart`.
- **Garde :** [ADR-0110](0110-un-seul-systeme-de-focus-dpad.md) (aucun gestionnaire de touches de
  plus, aucun second système de focus), ADR-0028 (hôte tvOS), la règle de `AppDelegate.swift` sur
  la session audio (seul le lecteur l'active).

## Contexte

Sur tvOS, le clic qu'on entend en se déplaçant est joué par le moteur de focus d'UIKit. Le guide
d'Apple le range parmi ce que ce moteur fait seul (« playing navigation sounds ») et précise qu'il
n'existe aucune API pour poser le focus ou le déplacer soi-même. Onyx est une app Flutter
(flutter-tvos) : c'est Flutter qui déplace le focus, UIKit ne voit rien bouger, et l'app est muette.

Ce que la recherche a établi :

- **Aucune API publique ne joue ce clic à la demande.** `UIFocusSoundIdentifier`,
  `soundIdentifierForFocusUpdate(in:)` et `UIFocusSystem.register(_:forSoundIdentifier:)` (tvOS 11)
  ne font que choisir le son d'un déplacement qu'UIKit mène déjà. Sur les forums d'Apple, la réponse
  du personnel à qui voulait intervenir sur ce son est « There's no API to accomplish this ».
- **Aucune API ne donne le réglage « Clics de navigation »** (Réglages, Vidéo et audio). Une réponse
  des forums suggère de le demander à Apple par un rapport ; rien n'est apparu depuis dans la
  documentation.
- **Les fichiers de ces sons existent dans le système**, dans `/System/Library/Audio/UISounds/` :
  `focus_change_small.caf`, `focus_change_large.caf`, `focus_change_app_icon.caf`,
  `focus_change_keyboard.caf`, `navigation_push.caf`, `navigation_pop.caf`. Ils figurent dans les
  listes de fichiers relevées sur iOS 26 et 27, et la table des sons du système leur donne les
  identifiants 1124 à 1129 (`FocusChangeSmall` = 1127, `NavigationPush` = 1128, `NavigationPop` =
  1129). **Ces relevés sont faits sur iOS** : qu'ils soient au même endroit sur tvOS est une
  déduction (même système, et ces sons n'ont d'usage que sur l'Apple TV), pas un constat.
- **System Sound Services existe sur tvOS et sert à cela** : `AudioServicesCreateSystemSoundID` et
  `AudioServicesPlaySystemSound` sont disponibles depuis tvOS 9. Apple les destine aux « user-interface
  sound effects (such as button clicks) » : un fichier `.caf` de moins de 30 s, joué aussitôt, sans
  réglage de volume. Et ces sons « are not subject to configuration using your audio session » :
  ils ne passent pas par l'`AVAudioSession` de l'app.
- **Apple ne garantit rien de tout cela.** Sa documentation dit que les sons d'interface fournis par
  le système « are not available to your iOS application » : ni les chemins ni les identifiants ne
  sont documentés, et ils peuvent changer sans préavis.

## Décision

1. **L'hôte rejoue les fichiers de son du système par System Sound Services**
   (`NavigationSound.swift`, canal `onyx/tv_navigation_sound`). Trois sons : `move`
   (`focus_change_small.caf`), `push` (`navigation_push.caf`), `pop` (`navigation_pop.caf`). Ils sont
   lus là où tvOS les range : rien n'est copié dans le dépôt ni dans l'app, ces fichiers sont à
   Apple.
2. **Le fichier d'abord, l'identifiant fixe à défaut.** Le nom du fichier dit ce qu'on joue ; si le
   fichier est absent ou refusé, l'hôte retombe sur l'identifiant que le système donne au même son
   (1127, 1128, 1129), qui doit rester sans effet s'il est inconnu (la fonction ne rend ni ne lève
   rien). Deux chemins indépendants vers le même son : chaque essai coûte une build TestFlight,
   autant ne pas dépendre d'un seul.
3. **Chargés une fois, joués sans rien allouer.** Dart envoie `prepare` au démarrage (si le réglage
   est actif) ; l'hôte crée les trois sons et répond d'où ils viennent (`file` ou `id`), ce que Dart
   écrit dans le journal de l'app. Jouer est ensuite un seul appel.
4. **Le clic part d'un seul endroit : l'écoute du `FocusManager`** (`TvNavigationSound`). C'est le
   seul point commun à l'ancien système, à dpad, aux flèches que des écrans traitent eux-mêmes et au
   pavé tactile. Il ne sonne que si un pas de direction vient d'être annoncé :
   - `TvTouchpad` annonce les touches (son observateur, qui n'existe que sur Apple TV) et les pas du
     pavé. Une flèche arme le clic, toute autre touche le désarme ;
   - le focus doit se poser dans les 250 ms (`stepWindow` : dpad fait parfois défiler 160 ms avant de
     réessayer). Un pas refusé au bord ne déplace rien, donc ne joue rien, comme sur tvOS ;
   - un pas, un clic, et jamais deux clics à moins de 80 ms (`minInterval`) : une flèche maintenue
     (110 ms) garde chaque clic, une rangée balayée au pavé (60 ms) n'en sonne qu'un sur deux.
   Un focus que personne n'a demandé (l'entrée d'une page, un focus rendu après un rechargement)
   reste muet, et une page qui s'ouvre ou se referme désarme le clic.
5. **Une page qui s'ouvre joue `push`, une page qu'on quitte joue `pop`**, par un observateur du
   navigateur racine. La première route (le démarrage) est muette.
6. **Le lecteur est muet de bout en bout** : son ouverture, son chrome et sa fermeture
   (`PlayerPresence`, et le nom de sa route). Rien ne se superpose à une bande-son ni au moment où
   le lecteur active la session audio.
7. **Un réglage dans l'app**, « Sons de navigation » (Cet appareil, groupe Son), activé par défaut,
   visible sur Apple TV seulement. Il existe parce que le réglage de tvOS ne peut pas être lu.
8. **Hors Apple TV, rien** : le service ne s'installe pas et aucun appel ne part vers le canal.

## Écarté

- **Faire jouer le clic par UIKit** (`soundIdentifierForFocusUpdate`, ou des vues natives invisibles
  entre lesquelles on ferait sauter le focus d'UIKit à chaque pas de Flutter). Ce serait le vrai
  son, au vrai volume, avec le réglage du système. Mais rien ne dit qu'UIKit sonne pour une mise à
  jour demandée par l'app plutôt que par la télécommande, et déplacer le focus d'UIKit hors de la vue
  de Flutter risque de lui retirer les touches. Impossible à mettre au point sans appareil.
- **`UIDevice.playInputClick()`** : c'est le clic du clavier, il demande une vue de saisie visible
  qui adopte `UIInputViewAudioFeedback`, et sa disponibilité tvOS n'est pas datée dans la
  documentation.
- **Embarquer un son et le jouer par `AVAudioPlayer`** : on n'a pas le droit de redistribuer les
  sons d'Apple, et un `AVAudioPlayer` passe par la session audio de l'app, que seul le lecteur doit
  activer (une session activée trop tôt fige la route en stéréo, AetherEngine issue #24).
- **Les identifiants fixes en premier** : `AudioServicesPlaySystemSound` ne rend rien, on ne saurait
  ni s'ils existent sur tvOS ni quoi écrire au journal.
- **Brancher le clic dans chaque moteur** (`TvDirectionalFocusAction`, `TvArrowGate`,
  `Dpad.onFocusChange`) : deux moteurs coexistent (ADR-0110, `legacy` livré par défaut) et des écrans
  déplacent le focus eux-mêmes ; le clic manquerait à certains pas, ou serait branché à quatre
  endroits. `Dpad.onFocusChange` sonnerait en plus pour chaque focus, demandé ou non.
- **Un son par taille de cible** (`focus_change_large.caf` pour les affiches) : la règle de tvOS
  n'est pas documentée, une supposition de plus à écouter. Une ligne à changer si besoin.
- **Un bruit au bord de l'écran** (`Dpad.onBlockedMove`) : tvOS n'en fait pas.

## Conséquences

- **Rien n'est acquis avant l'écoute.** Si l'Apple TV reste muette, lire dans le journal de l'app
  (Réglages, Cet appareil, Journal) la ligne `Sons de navigation : {move: …}` : `file` dit que le
  fichier du système a été trouvé et chargé, `id` qu'il ne l'a pas été. Pas de ligne : l'hôte n'a
  pas le canal, le fichier Swift n'est pas compilé.
- **Le réglage « Clics de navigation » de tvOS n'est probablement pas suivi.** Coupé dans les
  réglages de l'Apple TV, le clic peut continuer dans Onyx tant que le réglage d'Onyx est actif. À
  vérifier : si tvOS l'applique de lui-même, tant mieux.
- **Le volume est celui du fichier brut.** UIKit module peut-être son clic ; System Sound Services
  ne règle aucun volume. Si le clic d'Onyx est plus fort que celui de l'écran d'accueil, cette
  technique ne sait pas le baisser.
- **Zone grise pour l'App Review.** Les API sont publiques, mais ni le chemin des fichiers ni les
  identifiants ne le sont. Beaucoup d'apps jouent ainsi des sons du système ; le risque d'un refus
  est faible, pas nul.
- Le jour où `TvTouchpad` change ou disparaît, les deux annonces (`noteKey`, `noteStep`) le suivent ;
  sous dpad seul, `TvArrowGate` voit passer les mêmes pas.

### À écouter sur une vraie Apple TV

1. Le clic sort-il, sur le pavé directionnel et au glissé du pavé tactile ? Est-ce bien celui de
   l'écran d'accueil de tvOS, au même niveau ?
2. Flèche maintenue dans une rangée, glissé vif : la cadence est-elle agréable (80 ms au plus
   serré) ?
3. Au bord d'une rangée : silence.
4. Ouvrir une fiche, un menu, une fenêtre : `push`. Revenir : `pop`. Ces deux sons sont-ils à leur
   place, ou de trop ?
5. Lancer un film, naviguer dans son chrome, le quitter : aucun son d'Onyx, et la bande-son n'est ni
   coupée ni baissée. Un film en 5.1 sort toujours en 5.1.
6. Avec « Clics de navigation » coupé dans tvOS, puis « Effets sonores et musique » : qu'entend-on ?
7. Avec le réglage d'Onyx coupé : silence.
8. Sortie sur des HomePod ou des AirPods : le clic suit-il, sans retard gênant ?

## Sources

- Apple, *Controlling the User Interface with the Apple TV Remote* :
  <https://developer.apple.com/library/tvos/documentation/General/Conceptual/AppleTV_PG/WorkingwiththeAppleTVRemote.html>
- Apple, `soundIdentifierForFocusUpdate(in:)` :
  <https://developer.apple.com/documentation/uikit/uifocusenvironment/soundidentifierforfocusupdate(in:)>
- Apple, `UIFocusSystem.register(_:forSoundIdentifier:)` :
  <https://developer.apple.com/documentation/uikit/uifocussystem/register(_:forsoundidentifier:)>
- Apple, *Multimedia Programming Guide, Using Audio* (l'usage de System Sound Services, et la note
  sur la session audio) :
  <https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html>
- Apple, `AudioServicesPlaySystemSound(_:)` (tvOS 9, limites) :
  <https://developer.apple.com/documentation/audiotoolbox/audioservicesplaysystemsound(_:)>
- Apple, `AudioServicesCreateSystemSoundID(_:_:)` :
  <https://developer.apple.com/documentation/audiotoolbox/audioservicescreatesystemsoundid(_:_:)>
- Apple, `AudioServicesPlayAlertSound(_:)` (la note « not available to your iOS application ») :
  <https://developer.apple.com/documentation/audiotoolbox/audioservicesplayalertsound(_:)>
- Apple, `UIDevice.playInputClick()` :
  <https://developer.apple.com/documentation/uikit/uidevice/playinputclick()>
- Forums Apple, « Disable focus change sound ? » (réponse du personnel d'Apple) :
  <https://developer.apple.com/forums/thread/18996>
- Forums Apple, « Suppress focus sound? » (pas d'API pour lire le réglage) :
  <https://developer.apple.com/forums/thread/24733>
- Forums Apple, « Using system sound for a UI Alert » et « System Sound Path » (App Review) :
  <https://developer.apple.com/forums/thread/95221>, <https://developer.apple.com/forums/thread/95108>
- Fichiers et identifiants relevés sur iOS : <https://github.com/TUNER88/iOSSystemSoundsLibrary>,
  <https://github.com/p-x9/swift-system-sound/blob/main/SystemSoundTable.md>,
  <https://github.com/klaas/SwiftySystemSounds>
