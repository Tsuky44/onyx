# ADR-0126 — Le menu du compte met les profils en tête

- **Statut :** accepté. Design « B · profils en tête » choisi par l'utilisateur parmi quatre maquettes
  (2026-11-13) ; rendu vérifié sur une capture du panneau, pas encore vu sur appareil.
- **Date :** 2026-11-13
- **Portée :** `widgets/global/account_menu.dart` (`AccountMenu`), `account_menu_panel.dart`
  (`AccountMenuPanel`, `AccountMenuChoice`), `account_menu_route.dart` (`showAccountMenu`),
  `screens/auth/add_user_flow.dart` (`addUserAndSwitch`). Tous les appareils : le header de bureau, la
  barre du téléphone, la barre de l'accueil et le header du téléviseur montent le même `AccountMenu`.
- **Complète** l'[ADR-0078](0078-plusieurs-utilisateurs-sur-un-appareil.md) (plusieurs utilisateurs
  sur un appareil) et garde la règle de l'[ADR-0013](0013-plusieurs-serveurs-et-demandes-d-acces.md) : une ligne par autre
  serveur, aucune quand il n'y en a qu'un.

## Contexte

Le menu du compte était un `PopupMenuButton` Material : un nom, puis des lignes. Il ne ressemblait pas
au reste de l'app (pastilles de « Qui regarde ? », focus blanc à l'encre noire du lecteur et du dos des
affiches). Changer de personne, le geste le plus fréquent sur un appareil partagé, demandait deux écrans :
« Changer d'utilisateur », puis « Qui regarde ? ».

## Décision

1. **Les personnes du serveur en tête**, en pastilles (`ProfileDisc`, coins arrondis comme les
   affiches) avec leur nom dessous. La personne en cours porte un liseré blanc et reçoit le focus à
   l'ouverture. Une pastille bascule sur ce compte (`switchServer`), sans passer par « Qui regarde ? ».
2. **« Ajouter » au bout de la rangée** ouvre l'ajout d'un utilisateur puis passe sur son compte : le
   même chemin que « Qui regarde ? », sorti dans `addUserAndSwitch`.
3. **Sous la rangée, le serveur et le rôle**, puis les lignes : Gérer les profils (les images, par
   « Qui regarde ? »), Rejoindre une séance, Passer sur chaque autre serveur, Paramètres, Connecter un
   appareil (téléphone seulement), et Se déconnecter, en rouge, à part.
4. **Le focus et le survol remplissent une ligne de blanc à l'encre noire**, comme le dos des affiches
   et les boutons du lecteur ; la déconnexion se teinte de rouge pâle.
5. **Une route surgissante à soi** (`showAccountMenu`), posée sous l'avatar et alignée sur son bord
   droit, qui glisse vers la gauche sur un écran étroit et défile si la hauteur manque. Sur téléviseur, la
   page passe par `TvUiScale` puis grandit de `AppTheme.tvMenuBoost`, comme les autres menus.

### Écarté

- **A · carte de verre** (le menu actuel refait), **C · volet latéral**, **D · fiche centrée** : présentés
  ensemble, B retenu.

## Conséquences

- « Changer d'utilisateur » disparaît : la rangée le remplace, et « Gérer les profils » mène à
  « Qui regarde ? » pour changer une image.
- Le bouton du header n'est plus l'apparence d'un `PopupMenuButton` : `GlassIconButton` porte son propre
  `onTap` et son focus.
- Épinglé par `test/account_menu_test.dart` (contenu, choix rendus, ouverture sous le bouton, bascule en
  un geste, carte de la télécommande sur les deux systèmes de navigation).
