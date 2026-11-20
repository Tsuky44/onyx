# ADR-0161 — Les listes passent entièrement dans la matière Onyx

- **Statut :** accepté
- **Date :** 2026-11-20
- **Portée :** l'app seulement (`app/lib/screens/lists/`, `app/lib/widgets/global/watch_list_members_sheet.dart`,
  `watch_list_access_control.dart`, `list_visibility_choice.dart`, `watch_list_editor_dialog.dart`,
  `onyx_toast.dart`, `onyx_menu_route.dart`, `add_to_list_sheet.dart`,
  `app/lib/screens/player/widgets/onyx/onyx_capsule_button.dart`). Complète les ADR-0128, 0130, 0131
  et 0160 ; aucun changement de contrat ni de serveur.

## Contexte

La refonte de l'ADR-0160 avait rangé le détail d'une liste, mais plusieurs morceaux restaient en
composants Material d'origine, à côté de pages qui ont déjà la matière d'Onyx (menus de l'ADR-0130,
dialogues de l'ADR-0128, panneaux de l'ADR-0131) :

- « Partager » était une feuille du bas Material : un interrupteur (`SwitchListTile`), puis des
  `ListTile` qu'il fallait déplier pour choisir un rôle, en deux gestes par personne ;
- « Modifier la liste », « Supprimer » et « Déplacer / Copier vers… » étaient des `AlertDialog` ;
- l'en-tête portait un `FilledButton` et un `OutlinedButton`, la barre de sélection des
  `TextButton`, la vue d'ensemble un `PopupMenuButton`, et les messages des SnackBars ordinaires ;
- le partage avec tout le serveur se réglait à deux endroits (la fenêtre de modification et la
  feuille « Partager »).

Les maquettes validées par Tsuky (canevas « Onyx — refonte des listes ») fixent la cible.

## Décision

1. **Les boutons des listes sont les capsules du lecteur.** `OnyxCapsuleButton` (déjà employé hors
   du lecteur par la carte d'invitation) porte l'action principale en blanc (« Lire… », « Nouvelle
   liste »), le reste en verre ; il gagne un `leading` pour poser les visages des invités sur
   « Partager ». Les onglets Tous / À voir / Vus / À demander sont des capsules, l'onglet ouvert en
   blanc. « ⋯ » est un `GlassIconButton` qui déclenche un `OnyxMenuButton`.
2. **Le menu « ⋯ » se range en deux groupes titrés**, « La liste » et « Les titres », seulement
   quand les deux sont là ; ses lignes disent ce qu'elles touchent (« 2 personnes invitées »,
   « 3 titres · se défait »).
3. **« Partager » est un panneau adaptatif** (`showAdaptivePanel`, collé au bouton sur grand
   écran, feuille du bas ailleurs). Qui peut voir la liste se choisit entre deux cartes
   (`ListVisibilityChoice`) ; l'accès de chaque personne se règle en un geste : trois cases
   « Aucun · Voir · Ajouter » sur grand écran et au téléviseur, une capsule qui ouvre le menu des
   issues sur téléphone, où trois cases ne tiennent pas à côté d'un nom. Au-delà de six comptes,
   un champ filtre la liste. « À regarder plus tard » y a seulement le choix de qui la voit.
4. **Le partage ne se règle plus dans « Modifier la liste »**, qui devient un `OnyxDialog` (nom,
   description, compteurs). Seule la création d'une liste demande qui la voit, avec les mêmes
   cartes.
5. **« Supprimer » est un `OnyxDialog` destructif** qui montre ce qu'il emporte : les affiches,
   le nombre de titres, qui perd l'accès.
6. **« Déplacer / Copier vers… » est un menu Onyx collé à l'affiche ou au bouton**, chaque liste
   avec la mosaïque de ses affiches, « Mes listes » puis « Partagées avec moi », et
   « Nouvelle liste… » en pied, qui crée la liste avant d'y ranger. `showOnyxMenu` accepte pour
   cela une ancre par contexte (`anchorContext`) en plus d'une clé.
7. **La sélection flotte.** Sa barre se pose au bas de l'écran au lieu de remplacer les onglets :
   on garde sous les yeux l'onglet où l'on choisit. Une affiche cochée a un contour et une pastille
   blancs, le bleu restant aux barres de lecture.
8. **Les messages sont des toasts Onyx** (`showOnyxToast`) : une capsule sombre au filet de verre,
   passée par le `ScaffoldMessenger` (même file, même annonce aux lecteurs d'écran). Une copie ou un
   déplacement propose « Ouvrir » la liste d'arrivée.
9. **La lueur de l'en-tête** : la dernière affiche ajoutée, très floutée, se fond derrière
   l'en-tête du détail. Le mode léger et le téléviseur s'en passent (ADR-0025).

## Alternatives écartées

- **Garder l'interrupteur de partage dans les deux fenêtres** : deux réglages du même état, dont
  l'un enregistre tout de suite et l'autre à « Enregistrer ».
- **Trois cases aussi sur téléphone** : à 390 px, le nom de la personne tombait à quelques lettres.
- **Un composant capsule propre aux listes** : un second dessin de la même capsule.
- **« Marquer comme vu » dans la barre de sélection** : il demande une route (ADR-0160,
  Conséquences) ; maquetté, pas fait.

## Conséquences

- Sur un téléviseur, `OnyxMenuButton` et `OnyxDialog` gardent leur rendu Material de repli
  (ADR-0128, ADR-0130) : ce qui change au téléviseur, ce sont les capsules, les cartes de
  visibilité et les cases d'accès, toutes `TvFocusable`.
- `OnyxCapsuleButton` vit toujours sous `screens/player/widgets/onyx/` alors que trois écrans hors
  du lecteur l'emploient ; le monter dans `widgets/global/` avec ses couleurs de verre est un
  déplacement à faire à part.
- « Ajouter à une liste » (fiche d'un titre) prend le toast Onyx pour ses erreurs ; son panneau
  reste celui de l'ADR-0131.
