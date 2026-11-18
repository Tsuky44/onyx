# ADR-0141 — Le clavier d'un écran tactile se referme

- **Statut :** accepté. Demandé par l'utilisateur sur un iPhone (2026-11-18, « dans les recherches
  c'est complètement bugé, le clavier ne part jamais ») ; comportement épinglé par des tests sous
  iOS et Android simulés, **pas encore vu sur un iPhone**.
- **Date :** 2026-11-18
- **Portée :** `tv/tv_deferred_keyboard.dart` (`usesTouchKeyboard`, le toucher hors du champ, le
  champ « garé »), `widgets/global/glass_chrome.dart` (`GlassSearchInput`),
  `screens/library/search_results_screen.dart`,
  `screens/search/desktop/desktop_search_chips.dart`.
- **Prolonge** le rôle de `TvDeferredKeyboard`, par où passe chaque champ de l'app
  (`test/no_bare_text_field_test.dart`) : il règle aussi le clavier d'un écran tactile.

## Contexte

Sur un iPhone, rien ne refermait le clavier de la recherche, et il revenait de lui-même. Trois
causes, toutes vérifiées dans le code de Flutter 3.44 ou par un test :

- **Un toucher hors du champ ne fait rien sur iOS et Android.** L'action par défaut
  (`_EditableTextTapOutsideAction`) ne retire le focus que sur un bureau ou dans un navigateur.
  Toucher une affiche, faire défiler les résultats : le clavier restait.
- **La touche « Rechercher » ne fermait pas le clavier.** `GlassSearchInput` fournit
  `onEditingComplete`, et la documentation de Flutter le dit : le fournir retire le geste par
  défaut, qui retire le focus au champ.
- **Au retour sur une page, Flutter rend le focus au champ qui l'avait** : la barre de recherche
  sous les résultats, le champ des résultats sous une fiche. Il le rend dès la première image du
  retour, et le clavier se rouvrait sur une page qu'on ne faisait que regarder.

## Décision

Sur un écran tactile (`TvDeferredKeyboard.usesTouchKeyboard` : iOS ou Android d'après
`defaultTargetPlatform`, app installée ou navigateur, jamais un téléviseur) :

1. **Un toucher hors du champ le quitte** : `TvDeferredKeyboard` remplace l'action
   `EditableTextTapOutsideIntent`. Un autre champ n'est pas « hors » (ils partagent la région de
   `EditableText`), donc passer d'un champ à l'autre ne fait pas retomber le clavier.
2. **Un champ recouvert par une autre page ne peut plus prendre le focus** (`_parked`), jusqu'à
   ce que sa page soit revenue au premier plan et que celle qui partait ait rendu le focus. On y
   retape d'un toucher, comme avant.
3. **La touche « Rechercher » referme le clavier** (`GlassSearchInput.onEditingComplete`). La page
   des résultats ne pose plus le focus sur la première affiche au doigt : c'est un geste de clavier
   et de télécommande.
4. **Les pastilles de la recherche du bureau sont dans la région du champ**
   (`TextFieldTapRegion`) : les cliquer n'est pas quitter le champ. Le test qui le promettait ne
   passait que parce que Flutter, sous Android, ignore les touchers hors du champ ; sur un vrai
   bureau, le clic retirait le focus.

### Écarté

- **Fermer le clavier au défilement seulement** (`keyboardDismissBehavior.onDrag`). Un toucher
  sur une affiche ne défile pas, et il restait le retour sur la page.
- **Retirer le focus à la barre de recherche quand la page des résultats s'ouvre.** Le clavier
  retomberait puis remonterait sous le doigt, entre les deux champs.

## Conséquences

- Tout champ de l'app suit ces règles sur un téléphone : formulaires, Réglages, demandes. Ouvrir
  un menu ou un dialogue par-dessus un champ referme le clavier, qui ne revient pas seul.
- Les tests de l'app tournent par défaut sous Android : tous passent maintenant par ce chemin.
- Épinglé par `test/touch_keyboard_test.dart` (iOS et Android : toucher hors du champ, autre
  champ, retour sur la page, touche « Rechercher » ; au bureau, Entrée garde le champ).
