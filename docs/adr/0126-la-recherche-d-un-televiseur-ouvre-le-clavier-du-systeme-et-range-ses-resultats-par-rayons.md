# ADR-0126 — La recherche d'un téléviseur ouvre le clavier du système et range ses résultats par rayons

- **Statut :** accepté. Rendu vérifié sur une capture de l'app à 1280 × 720 ; pas encore vu sur une
  Apple TV, et le clavier du système ne se voit que là. Sur l'Apple TV, remplacé par
  l'[ADR-0129](0129-sur-l-apple-tv-la-recherche-est-l-ecran-du-systeme-et-montre-les-titres-absents.md)
  (l'écran de recherche du système) ; il reste la recherche des autres téléviseurs.
- **Date :** 2026-11-13
- **Portée :** `screens/search/tv_search_screen.dart` (`TvSearchScreen`),
  `widgets/global/glass_catalog_search.dart` (`_openTvSearch`), `widgets/global/glass_chrome.dart`
  (`GlassSearchInput.large`), `widgets/global/tv_poster_wall.dart` (`TvPosterWall`).
- **Prolonge** l'[ADR-0117](0117-la-barre-d-onglets-d-un-televiseur-est-une-pilule-centree.md) (la loupe ouvre la recherche
  depuis la pilule des onglets) et
  l'[ADR-0125](0125-la-bibliotheque-d-un-televiseur-pose-la-fiche-a-gauche-et-la-grille-a-droite.md)
  (le mur d'affiches).

## Contexte

Demande de l'utilisateur, sur Apple TV : « remplace comment marche la recherche, fais un truc beaucoup
mieux, un truc comme l'app Emby sur Apple TV ».

La recherche d'un téléviseur était la page du bureau (`SearchResultsScreen`) : une barre d'app avec un
champ de 34 px, et dessous la grille du bureau, sept petites affiches par ligne sous « Résultats pour
« … » ». Avant de taper, un écran vide.

Une première version dessinait un clavier dans la page, lettres et chiffres en grille à côté des
résultats. L'utilisateur l'a refusée avant qu'elle parte : « c'est sur Apple TV, donc faut que ça
matche parfaitement, ça doit ouvrir le clavier Apple pour qu'on puisse parler et utiliser la dictée ».

## Décision

**Sur téléviseur, la recherche est une page à elle (`TvSearchScreen`) : le champ en tête, qui ouvre le
clavier du système, et dessous les résultats rangés par rayons.**

1. **Le clavier est celui du système, jamais un clavier de l'app.** C'est lui qui porte la dictée et
   la saisie depuis un téléphone. Il s'ouvre en même temps que la page : un seul OK sur la loupe, et
   l'on parle ou l'on tape.
2. **Refermé, le champ redevient un bouton** (`TvDeferredKeyboard`) : le traverser ne rouvre rien, OK
   rouvre le clavier sur ce qui est déjà tapé.
3. **Valider pose la télécommande sur le premier résultat.** Le clavier se referme et il n'y a pas de
   pas de plus à faire. Sans résultat, elle reste dans le champ.
4. **Les résultats sont rangés par rayons**, les films puis les séries, chacun sous son nom et son
   compte (« Films · 4 »). Un rayon sans résultat n'est pas dessiné.
5. **Avant de taper, la page propose les douze derniers ajouts** au lieu d'un écran vide.
6. **Les affiches sont celles de l'accueil** : six par ligne, 177 × 266 px, et elles défilent rangée
   par rangée (`TvPosterWall`). L'affiche focalisée porte son cartouche (titre, type, résumé) : il n'y
   a pas de fiche à côté pour le dire.
7. **Le champ est grand et centré** (640 × 48 px, `GlassSearchInput.large`) : c'est ce qu'on lit de
   loin, pas un champ parmi d'autres dans une barre. Les rangées déjà vues s'estompent en passant
   dessous.
8. **La recherche reste celle du catalogue chargé** (`LibraryProvider.searchCatalog`) : aucune
   requête, aucun changement du serveur.

Hors téléviseur, la recherche ne change pas.

### Écarté

- **Un clavier dessiné dans la page**, à côté des résultats. Écrit, testé, puis retiré à la demande de
  l'utilisateur : il n'a ni la dictée ni la saisie depuis un téléphone, et il double celui du système.
- **Le clavier en ligne de tvOS** (`UISearchController`), celui de l'app TV d'Apple et d'Emby : une
  rangée de lettres en tête d'écran, les résultats visibles dessous pendant qu'on tape. Il demande du
  code natif (un contrôleur présenté par-dessus la vue Flutter, le focus rendu d'un monde à l'autre),
  impossible à essayer sans appareil. À faire avec des builds d'essai si l'utilisateur le demande. D'ici
  là le clavier du système couvre l'écran pendant la saisie, et les résultats se voient quand il se
  referme.
- **Des résultats en rangées horizontales**, comme l'accueil. Douze affiches visibles en grille contre
  six par rangée, et une recherche rend souvent un seul rayon.

## Conséquences

- **Android TV et le web des téléviseurs LG** prennent la même page (`TvScope`), avec leur propre
  clavier.
- `SearchResultsScreen` ne sert plus sur téléviseur ; elle reste la page du téléphone et du bureau.
- **Les résultats changent à chaque caractère**, mais sous le clavier du système on ne les voit qu'à
  sa fermeture.
- Épinglé par `test/tv_search_screen_test.dart` (ouverture du clavier, rayons, validation, retour au
  champ, Retour ; les deux systèmes de navigation) et `test/tv_glass_search_test.dart` (la loupe ouvre
  cette page).
