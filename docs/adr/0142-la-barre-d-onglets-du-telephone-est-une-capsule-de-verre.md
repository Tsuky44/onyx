# ADR-0142 — La barre d'onglets du téléphone est une capsule de verre, et la recherche s'y étire

- **Statut :** accepté. Maquette validée par l'utilisateur (2026-11-18 : « la bis est bien », puis
  pour l'ouverture de la recherche « ok c'est validé, code tout ») ; rendu vérifié sur des images
  de la barre en 390 × 844, **pas encore vu sur un iPhone**.
- **Date :** 2026-11-18
- **Portée :** `screens/shell/mobile_bottom_nav.dart` (réécrit), `screens/shell/phone_search.dart`
  (nouveau : `PhoneSearchSession`, `PhoneSearchField`, `TabBarScrollWatch`),
  `screens/shell/main_shell.dart`, `screens/shell/mobile_top_bar.dart`,
  `screens/library/search_results_screen.dart` (`SearchResultsScreen.docked`, remplacée depuis par
  `PhoneSearchScreen`, [ADR-0145](0145-sur-telephone-la-recherche-est-une-page-sous-la-bulle.md)),
  `widgets/global/sliver_scroll_end.dart` (nouveau), la fin des pages qui défilent (accueil,
  bibliothèques, demandes, listes, hors ligne, fiches) ; `widgets/global/sticky_glass_search.dart`
  est retiré.
- **Remplace** la barre pleine largeur en verre sombre et dense du téléphone, et le champ de
  recherche de sa barre du haut. **Prolonge** l'[ADR-0141](0141-le-clavier-d-un-ecran-tactile-se-referme.md)
  (la barre laisse la place à un autre clavier que le sien).

## Contexte

L'utilisateur voulait la barre d'onglets du téléphone « dans le même style que sur Apple TV (mais
en bas), style liquid glass » : la pilule de verre de l'ADR-0117, posée où le pouce l'attend. La
barre d'avant prenait toute la largeur et 90 points de haut, en verre si dense qu'il ne laissait
rien voir dessous ; le champ de recherche était en haut, loin du pouce, et le clavier qu'il
ouvrait remontait la barre d'onglets avec lui.

Sur la maquette, l'utilisateur a choisi « B bis », la capsule compacte, plutôt que la pilule de
l'Apple TV telle quelle (cinq noms ne tiennent pas sur un iPhone) ; puis l'ouverture de la
recherche en quatre images : le rond s'étire, le clavier monte, le champ se pose dessus.

## Décision

1. **Une capsule de verre qui flotte** (`MobileBottomNav`), 52 points de haut, à 16 points des
   bords et juste au-dessus de l'indicateur d'accueil : icône et nom de chaque onglet, une
   lentille de verre clair sous l'onglet affiché. Le verre est un voile clair dégradé sur un flou
   de ce qui passe dessous, un liseré et une ombre courte ; en mode léger et sur un téléviseur LG,
   un fond dense sans flou (`glassBlurs`).
   La même barre sur iPhone, iPad et Android (le code du téléphone est commun) ; au-dessus des
   trois boutons de navigation d'Android, plus hauts que l'indicateur d'accueil, elle se pose
   au-dessus d'eux au lieu de les chevaucher (`MobileBottomNav.bottomFor`).
2. **La recherche est un rond de verre à côté de la capsule**, comme la loupe au bout de la pilule
   de l'Apple TV. La barre du haut perd son champ : deux champs de recherche à l'écran laissaient
   le doute sur celui qui commande.
3. **Le rond s'étire sur toute la largeur et devient le champ** (`PhoneSearchSession.expand`,
   320 ms) pendant que les onglets se resserrent et s'effacent dessous ; la page des résultats
   s'ouvre derrière en fondu (`SearchResultsScreen.docked`). Quand la bulle a fini de s'étirer, le
   champ prend la main : le clavier monte au rythme du système, et la bulle monte avec lui, posée
   juste au-dessus. Sous « réduire les animations », sans mouvement.
4. **La page de recherche suit la frappe** : avant la frappe, son titre et les recherches
   récentes du profil (les mêmes que celles du bureau, `RecentSearches`) ; ensuite, les résultats.
   Une recherche rejoint les récentes quand elle a servi : touche « Rechercher », ou une fiche
   ouverte depuis les résultats.
5. **La croix referme la recherche**, fiches ouvertes depuis les résultats comprises ; Retour et
   le geste de retour d'iOS aussi. La bulle redevient un rond, les onglets reviennent.
6. **La page qui défile vers le bas réduit la capsule** à l'onglet affiché, la recherche reste
   (`TabBarScrollWatch`) ; elle revient en entier au premier geste vers le haut, en haut de page,
   au changement d'onglet, ou d'un toucher sur elle.
7. **Les pages passent sous la capsule** : la coquille leur donne sa place comme marge du bas,
   et leur fin la lit (`SliverScrollEnd`). La dernière rangée s'arrête au-dessus du verre ; le
   bouton flottant des demandes, posé par le `Scaffold`, monte d'autant.

### Écarté

- **La pilule de l'Apple TV telle quelle** (texte seul, la loupe dedans) : la plus fidèle à la TV,
  mais elle défile dès cinq onglets sur un iPhone.
- **La capsule de 62 points** de la première proposition : jugée « un peu haute ».
- **Le champ en haut de la page de résultats**, clavier en bas : le pouce allait chercher en haut
  ce qu'il venait d'ouvrir en bas.

## Conséquences

- Une page qui finit sur une marge fixe passe sous la capsule : la fin d'une nouvelle page
  défilante est un `SliverScrollEnd`, ou lit `SliverScrollEnd.extentOf`.
- `GlassCatalogSearch` ne sert plus qu'au téléviseur ; son chemin téléphone (la page de résultats
  ouverte par la frappe dans la barre) reste, sans appelant sur un téléphone.
- Épinglé par `test/phone_tab_bar_test.dart` (la capsule et le rond, la bulle pleine largeur et
  la page derrière, la croix, Retour, la bulle au-dessus du clavier, la capsule réduite, le
  défilement, la place des pages, la lentille qui glisse, la fermeture à l'envers, la fiche
  ouverte depuis les résultats) et `test/touch_keyboard_test.dart` (la barre sous un autre
  clavier).

## Complément du 2026-11-18 : les gestes après l'essai sur l'iPhone

Après l'essai de la release test sur un iPhone (« c'est très bien »), l'utilisateur a demandé
trois mouvements :

1. **La lentille glisse d'un onglet à l'autre** (`_TabRow`). Une seule lentille pour toute la
   capsule, et non plus une par onglet : ses deux bords partent ensemble, celui de devant sur une
   courbe plus vive (`easeOutCubic`) que celui qui suit (`easeInOutCubic`), si bien qu'elle
   s'étire en chemin et se resserre en se posant. [AppMotion.emphasis] (260 ms), et interrompue
   elle repart d'où elle est. Sous « réduire les animations », elle se pose d'un coup.
2. **La fermeture joue l'ouverture à l'envers.** La croix, Retour ou un onglet touché : le clavier
   descend d'abord, la bulle posée sur lui, puis elle redevient un rond et les onglets
   reviennent. Avant, la barre se cachait tant que le clavier était encore là (la règle de
   l'ADR-0141 pour un autre champ), puis réapparaissait d'un coup. La bulle attend que la vue
   dise que le clavier est parti, 450 ms au plus.
3. **Une fiche ouverte depuis les résultats rend la capsule.** La page des résultats prévient la
   session quand une page la recouvre ([PhoneSearchSession.isCovered]) : la bulle redevient un
   rond, de la même façon qu'à la fermeture, et la capsule revient avec ses onglets. Au retour
   sur les résultats, la bulle se redéploie **sans rouvrir le clavier**, qui cacherait les
   résultats retrouvés. Le rond touché depuis la fiche ramène aux résultats, et là le champ prend
   la main. Un onglet touché depuis la fiche referme tout, comme avant.

La coquille ne laisse la place de la bulle sous ses pages que lorsqu'elle est déployée
([PhoneSearchSession.isExpanded]) ; une fiche ouverte depuis les résultats a la marge normale
de la capsule.

## À vérifier sur l'appareil

| Quoi | Pourquoi ici seulement |
| --- | --- |
| Le flou de la capsule sur des affiches qui défilent | Le coût du flou et son rendu dépendent du GPU. |
| La bulle qui monte avec le clavier, sans saut | Le rythme du clavier d'iOS ne se simule pas. |
| La capsule contre l'indicateur d'accueil | Les zones sûres réelles, pas celles d'un test. |
| La réduction au défilement sur une longue page | La cadence d'un vrai doigt. |
| La lentille qui s'étire entre deux onglets | L'effet se juge à l'œil, à 60 ou 120 Hz. |
| La bulle qui attend la descente du clavier | Le clavier réel annonce sa fin, pas celui du test. |
