# ADR-0154 — Le bandeau d'une série lance son épisode et fait défiler ses images

- **Statut :** accepté. Maquettes « Bandeau série Onyx » : la A choisie par l'utilisateur le
  2026-11-18, sans la capsule autour des traits et sans la carte « À suivre » sur téléphone (« ça
  fait trop chargé »), puis « on prend la A mais avec le fond vivant comme la E ». Vérifié en test,
  **pas encore vu dans l'app lancée** (ni bureau, ni iPhone).
- **Date :** 2026-11-18
- **Portée :** le bandeau d'accueil hors téléviseur. `widgets/global/hero_banner.dart`,
  `widgets/global/hero_carousel.dart`, `widgets/global/hero/` (nouveau : `hero_actions.dart`,
  `hero_heading.dart`, `hero_living_backdrop.dart`, `hero_next_episode_card.dart`,
  `hero_page_dashes.dart`), `services/hero_series_preview.dart` (nouveau),
  `screens/home/home_screen.dart` (`_onHeroPlay`), `widgets/global/detail_actions.dart`
  (`episodeShortCode`), `widgets/global/media_logo_display.dart` (l'ombre retirée).

## Contexte

Une série passait dans le bandeau comme un film : « SÉRIE », le logo, l'année, le résumé, « Lecture »
et « Plus d'infos ». « Lecture » n'y lançait rien : il ouvrait la fiche, comme « Plus d'infos ».
Rien ne disait où l'on en était, ni qu'un épisode venait de sortir. Les boutons, gris plats, ne
ressemblaient plus aux pièces de verre du téléphone (ADR-0142, ADR-0144), et le logo traînait
derrière lui un rectangle sombre et flou, l'ombre de sa boîte de 560 px.

## Décision

1. **La lecture lance l'épisode, et le dit.** Pour une série de la découverte, le bandeau demande au
   serveur l'épisode à reprendre (`/api/shows/{id}/resume`, celui de la fiche) ; une diapositive de
   « Reprendre » connaît déjà le sien. Le bouton devient « Reprendre S2 E4 » ou « Lecture S1 E1 »,
   le numéro plus pâle, écrit comme sur la fiche (`episodeShortCode`). Tant que le serveur n'a pas
   répondu, « Lecture » seul ouvre la fiche, comme avant.
2. **Le surtitre et la ligne d'infos.** « SÉRIE · 3 SAISONS », et une pastille « Nouvel épisode »
   quand l'épisode à lancer vient de sortir. Sous le titre : l'année, deux genres, la note TMDB,
   puis, pour une série, « Prochain épisode le … » (la règle du compte à rebours de la fiche).
3. **La carte « À suivre », sur grand écran seulement** (à partir de 1000 px, hors téléviseur) :
   l'image de l'épisode, sa barre de progression, « S2 E4 · Le phare » et le temps restant, en verre
   liquide, à droite du texte. La toucher lance l'épisode. Pas sur téléphone.
4. **Le fond vivant** (`HeroLivingBackdrop`). L'image de la série, puis celles d'épisodes de la
   saison de l'épisode à lancer, **jusqu'à lui compris et jamais après** : au plus trois, réparties
   sur la saison (`pickHeroStills`). Fondu de 900 ms toutes les quatre secondes, zoom lent sur
   chaque image, une légende « S1 E5 · La tempête » au-dessus de la carte ou, au téléphone, à
   hauteur des traits. Une image seule (un film) zoome une fois, puis se fige.
5. **La diapositive reste le temps de ses images** : quatre secondes par image, sept au moins,
   seize au plus. Le carrousel passe d'une minuterie périodique à une minuterie par diapositive, et
   le survol suspend le temps passé sans le remettre à zéro.
6. **Les boutons et les traits.** Lecture en pilule ; « Plus d'infos » en verre liquide, réduit à
   son rond au téléphone. Le trait de la diapositive affichée se remplit à mesure qu'elle passe,
   sans capsule autour.
7. **Le logo perd son ombre portée**, partout : une `BoxShadow` ombre la boîte, pas les lettres.

Le téléviseur garde ses boutons, ses traits immobiles et un fond fixe (ADR-0112) ; le mode léger
et « réduire les animations » gardent eux aussi le fond fixe.

### Écarté

- **« + Ma liste » dans le bandeau**, sur la maquette : `AddToListButton` demande l'appartenance
  aux listes de chaque titre affiché, huit requêtes de plus à l'ouverture de l'accueil, pour un
  geste que la fiche porte déjà.
- **Les images des épisodes d'après** : plus d'images pour une série commencée, mais une image en
  dit parfois plus que le résumé.
- **Un fond qui défile plus vite pour tenir en sept secondes** (2,3 s par image) : le zoom n'avait
  pas le temps de se voir.

## Conséquences

- Une série au fond vivant fait deux requêtes de plus que le bandeau d'avant (l'épisode à
  reprendre, la liste de sa saison), une seule pour une reprise. `HeroSeriesPreviewCache` les garde
  dix minutes et les partage entre bandeaux ; l'accueil l'oublie au retour du lecteur.
- Une série jamais commencée n'a que l'image de son premier épisode en plus de la sienne.
- Le résumé passe à deux lignes sur grand écran quand la carte est là.
- Épinglé par `test/hero_series_slide_test.dart` (rien d'après l'épisode à lancer, la saison et
  les images, le premier épisode, la requête partagée, l'oubli au retour du lecteur, le bouton qui
  dit l'épisode, la carte absente du téléphone, le nombre d'images, le fond immobile sous
  « réduire les animations », la diapositive qui reste seize secondes, le logo sans ombre).

## À vérifier dans l'app

| Quoi | Pourquoi ici seulement |
| --- | --- |
| Le fondu entre deux images TMDB, sans passage par le noir | Le décodage réel des images. |
| Le zoom lent sur un grand écran et sur un iPhone | Le coût et la fluidité dépendent du GPU. |
| La carte « À suivre » à côté d'un logo très large | Les vraies proportions des logos. |
| Le trait qui se remplit pendant le survol puis la reprise | Le geste d'une vraie souris. |
