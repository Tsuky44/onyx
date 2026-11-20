# ADR-0148 — On invite à une séance les personnes qui ont Onyx ouvert

- **Statut :** accepté. Couvert par les tests (serveur et app) ; **pas encore essayé à deux appareils
  sur un vrai serveur**, ni à la télécommande sur Android TV et Apple TV.
- **Date :** 2026-11-18
- **Portée :** le serveur (`server/handlers/watch_party_invites.go`, quatre routes, la capacité
  `watch_party_invites`, `JoinWatchParty` et `RunWatchParties` dans `watch_party.go`), et côté app
  `services/watch_party_invites.dart` (`WatchPartyInviteInbox`), `services/api/watch_party_invites.dart`,
  `models/watch_party_invite.dart`, `widgets/global/watch_party_invite_card.dart`,
  `widgets/global/watch_party_invite_banner.dart`, `screens/home/home_screen.dart`,
  `screens/player/hooks/use_player_invite.dart` (`PlayerInviteWatch`),
  `screens/player/widgets/player_invite_overlay.dart`,
  `screens/player/widgets/tabs/player_watch_party_invitees.dart`. Prolonge l'ADR-0029.

## Contexte

Une séance « Regarder ensemble » (ADR-0029) se rejoignait seulement par son code : l'hôte le lisait
dans l'onglet du lecteur, le dictait, et l'autre l'entrait dans *menu du compte › Rejoindre une
séance*. Demande de l'utilisateur : « en plus du code, on puisse envoyer une invite aux personnes qui
sont connectées à l'app ; je ne veux pas qu'on puisse envoyer à une personne qui n'a pas l'app
ouverte ». L'invitation arrive en carte sur l'accueil, comme la lecture d'un autre appareil
(ADR-0127) ; pendant un film, elle arrive quand même, mais ne reste que dix secondes, avec de quoi
la fermer ou rejoindre. Sur toutes les plateformes.

## Décision

### 1. « Avoir Onyx ouvert », c'est attendre sa boîte d'invitations

Tant que l'app est vue (au premier plan, fenêtre ni réduite ni cachée) et connectée, elle attend en
long-polling `GET /api/me/watch-party-invites?since=N` sur le serveur actif, vingt secondes au plus,
comme une séance (ADR-0029). Le serveur note chaque attente par session : un compte est « présent »
si l'un de ses appareils a attendu depuis moins de 45 s. En arrière-plan, l'app coupe l'attente
(`WatchPartyInviteLifecycle`, sur le même signal que `AppForeground`) et le compte sort de la liste
en moins d'une minute.

Pas de nouvelle route de présence, pas de WebSocket : l'attente qui apporte les invitations est
celle qui prouve qu'on est là. Elle coûte une requête toutes les vingt secondes par appareil ouvert.

### 2. On n'invite que les personnes présentes

`GET /api/watch-parties/:code/invitees?member=ID` liste, à un participant de la séance seulement,
les comptes présents, sauf lui-même et ceux déjà dans la séance, avec où en est leur invitation
(« pending », « declined »). `POST /api/watch-parties/:code/invite` refuse un compte absent (`409`) :
le serveur décide, l'app ne fait qu'afficher (`onyx-engineering`).

Une invitation vit **deux minutes**, et tant que sa séance existe. Réinviter la même personne
remplace l'invitation par une nouvelle, qui s'affiche de nouveau. Huit invitations en attente au
plus par compte. Rejoindre la séance (par l'invitation ou par le code) retire l'invitation de tous
les appareils du compte ; refuser (`POST /api/me/watch-party-invites/:id/decline`) aussi, et le
refus reste dix minutes dans la liste de l'hôte (« A refusé », « Réinviter »). Tout est en mémoire,
comme les séances.

L'invitation porte le média **que la séance lit au moment de la réponse**, tel que le compte invité
le voit : une séance passée à l'épisode suivant invite à celui-là, et un média que ce compte ne
peut pas lire ne s'annonce pas.

### 3. Sur l'accueil, une carte à côté de la lecture d'un autre appareil

`WatchPartyInviteBanner` pose la carte sous la notification « En lecture sur… », en haut à droite ;
sur un téléphone, au-dessus de la sienne, en bas. Même verre, même largeur, même entrée animée. Elle
dit qui invite, à quoi, et a deux boutons : « Ignorer » (refuse) et « Rejoindre ». Elle reste
jusqu'à ce qu'on y réponde ou qu'elle expire.

Sur un téléviseur, Apple TV comprise, « Rejoindre » **prend le focus** à l'arrivée de l'invitation
et au retour sur l'accueil ; gauche mène à « Ignorer ». Contrairement à la lecture d'un autre
appareil (ADR-0127, ADR-0136), il n'y a pas de touche maintenue : une invitation est un message
qu'on vient de recevoir, pas une lecture qui partirait d'un geste machinal, et OK sur un bouton
nommé « Rejoindre » est un geste voulu.

Rejoindre ouvre le lecteur comme le code (`openJoinedWatchParty`, sorti de
`join_watch_party_dialog.dart`).

### 4. Pendant un film, dix secondes en haut à droite

`PlayerInviteWatch` montre l'invitation par-dessus tout le reste du lecteur, sur le verre du
lecteur (`OnyxGlassPanel`), dix secondes ; un trait sous les boutons dit le temps qui reste. Sans
réponse, elle s'efface et est tenue pour **vue** : elle ne revient ni dans le lecteur ni sur
l'accueil, et l'hôte la voit toujours « envoyée » jusqu'à son expiration. « Ignorer », et Retour
devant la carte, la refusent.

Sur un téléviseur et à l'ordinateur, « Rejoindre » prend le focus pendant ces dix secondes ; le
lecteur le reprend quand la carte s'en va. Sur un écran tenu en main, on répond du doigt.

**Rejoindre ne ferme pas le lecteur.** La séance rejointe devient la séance active ; le lecteur s'y
accroche (`PlayerWatchParty.sync`) et, s'il lit autre chose, ouvre son média par le même chemin
qu'un épisode suivant demandé par la séance (ADR-0029, point 5). Une séance déjà en cours ici est
quittée.

### 5. L'onglet de la séance liste qui inviter

Sous les participants, « Inviter » liste les personnes présentes, chacune avec son bouton
(« Inviter », « Envoyée », « Réinviter »), relue toutes les six secondes tant que l'onglet est
ouvert. Personne d'autre en ligne : l'onglet le dit, et le code reste le moyen.

### Écarté

- **Une notification système** (FCM, APNs). Elle atteindrait une app fermée, ce que l'utilisateur
  ne veut pas, et demanderait un service de notification qu'Onyx n'a pas.
- **Une présence déduite des sessions récentes** (`/api/me/devices`, dernier appel). Un appareil qui
  a appelé il y a deux minutes n'a pas forcément l'app ouverte, et l'invitation tomberait dans le
  vide.
- **Garder la carte du lecteur jusqu'à la réponse.** Elle couvrirait le film ; c'est ce que la
  demande exclut.
- **Une touche maintenue pour rejoindre sur Apple TV**, comme la reprise. Une carte qu'on ne peut
  viser qu'en la maintenant, et qui disparaît en dix secondes pendant un film, ne se rejoindrait
  presque jamais.

## Conséquences

- **Un compte présent sur un autre serveur que celui de la séance n'est pas listé** : la boîte
  n'attend que sur le serveur actif, comme une séance ne vit que sur un serveur (ADR-0029).
- **Sur un compte partagé**, l'invitation arrive sur tous les appareils ouverts du compte, et
  l'hôte ne peut pas s'inviter lui-même sur un autre de ses appareils : le code reste le moyen.
- **Une invitation arrivée pendant qu'on est sur une autre page** (une fiche, la recherche) attend
  le retour sur l'accueil, dans sa limite de deux minutes.
- Un appareil qui garde Onyx ouvert sans le regarder (un téléviseur resté sur l'accueil) reste
  invitable : la présence dit que l'app est vue par le système, pas qu'on la regarde.
- Épinglé par `server/handlers/watch_party_invites_test.go` (absent refusé, réveil de la boîte,
  réinvitation, refus vu par l'hôte, expiration et fin de séance, liste des présents seulement) et
  `app/test/watch_party_invites_test.dart` (boîte, carte, dix secondes, Retour, rejoindre depuis le
  lecteur, onglet) ; le format, par `contract/watch_party_invites.json` et
  `contract/watch_party_invitees.json`.
