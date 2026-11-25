# ADR 2026-11-25 (tsuky) : les notifications arrivent tout de suite, par un relais aveugle

- **Statut :** proposé. Recherche faite, rien n'est codé. Trois points attendent la décision de
  Tsuky et Mathis (voir « Questions ouvertes »).
- **Date :** 2026-11-25
- **Portée :** un nouveau service, le relais (`relay/`, Go), le serveur (inscription au relais,
  appareils à prévenir, envoi des évènements), l'app Android et iPhone/iPad (jeton de push, clé de
  l'appareil, déchiffrement, affichage par `OnyxNotifications`), et une extension de notification
  iOS. Téléviseurs, ordinateurs et web ne sont pas concernés.
- **Prolonge :** [ADR-0059](0059-notifications-de-nouveaux-episodes.md) et
  [ADR-0077](0077-notification-des-nouvelles-demandes.md), dont il revoit le §1 (« pas de push »).
  Respecte [ADR-0013](0013-plusieurs-serveurs-et-demandes-d-acces.md) : aucun serveur n'a besoin du
  relais pour fonctionner.

## Contexte

Aujourd'hui, l'appareil va demander à chacun de ses serveurs s'il y a du nouveau (ADR-0059,
ADR-0077) :

- **Android :** toutes les 15 minutes au mieux (plancher de WorkManager), plus tard chez les
  constructeurs qui tuent les tâches de fond.
- **iPhone :** quand iOS le décide. Ça peut être des heures plus tard, ou jamais si l'app a été
  balayée du sélecteur.

Tsuky veut des notifications « en direct le plus possible », d'abord pour les demandes. Et le
serveur sait déjà tout à la seconde : OnyxHub lui envoie par webhook (`POST
/api/integrations/mediahub/events`) les évènements `created`, `status_changed` et `imported`. Il ne
lui manque qu'un moyen de réveiller le téléphone.

### Ce qu'imposent Apple et Google

Sur iPhone, une app fermée ne reçoit rien en direct sans APNs. Sur Android, la seule autre voie est
une connexion permanente, avec une notification posée en permanence dans la barre d'état. Or APNs
et FCM n'acceptent que les envois signés par **l'éditeur de l'app** : la clé APNs (`.p8`) est liée
à notre Team ID et à notre bundle ID, et le compte de service FCM à notre projet Firebase. Un
serveur auto-hébergé ne peut pas détenir ces clés. Les lui donner, ce serait les publier.

Les autres projets auto-hébergés sont tous tombés sur ce mur, et presque tous l'ont réglé de la
même manière :

| Projet | Solution | Ce que voit le service central |
|---|---|---|
| Nextcloud | Proxy de push central. Le serveur chiffre avec la clé publique de l'appareil et signe. | Jeton et métadonnées, pas le contenu. |
| ntfy | Le serveur auto-hébergé envoie un `poll_request` à ntfy.sh, qui ne porte qu'un ID. L'iPhone va chercher le message sur le serveur. | Un ID de message. |
| Bitwarden | Relais `push.bitwarden.com`, avec un ID et une clé d'installation par serveur. | Une notification « synchronise-toi ». |
| Home Assistant | Relais Firebase central, limité à 500 notifications par jour et par appareil. Le « Local Push » en WebSocket ne marche qu'avec l'app ouverte ou une notification permanente. | Le contenu, en clair. |
| Overseerr / Jellyseerr | Web Push (VAPID) pour le site installé en PWA. | Pas d'app native. iOS limité. |

## Décision proposée

### 1. Un relais central qui ne sait rien : il porte des enveloppes fermées

Le projet héberge **un seul petit service**, le relais. C'est le seul endroit où vivent la clé APNs
et le compte de service FCM. Il ne lit rien et ne garde rien : il reçoit d'un serveur une
enveloppe chiffrée et un jeton d'appareil, puis la transmet à Apple ou Google.

```
OnyxHub ─webhook─▶ serveur Onyx ─(enveloppe chiffrée + jeton)─▶ relais ─▶ FCM / APNs ─▶ téléphone
                   (chez chacun)                                (projet)                 déchiffre
                                                                                        et affiche
```

- **Le contenu est chiffré de bout en bout**, de l'appareil au serveur. Pour chaque compte, l'app
  crée une paire de clés X25519 sur l'appareil et confie la clé publique à **son** serveur. Le
  serveur chiffre ainsi : X25519 éphémère, puis HKDF-SHA256, puis AES-256-GCM. Ce sont des
  briques standard partout : `crypto/ecdh`, `crypto/hkdf` et `crypto/cipher` dans la bibliothèque
  standard Go, CryptoKit côté Swift, et `cryptography` côté Dart (à ajouter). Le relais, Apple et
  Google voient un jeton, une taille et une heure. Ils ne voient ni le titre, ni le nom du compte,
  ni l'adresse du serveur.
- **L'enveloppe contient déjà tout ce qu'il faut afficher** : titre, texte, compte, série ou
  demande à ouvrir, adresse de l'affiche. Elle fait au plus environ 3 Ko, sous la limite de 4 Ko
  d'APNs et de FCM. On écarte donc le modèle ntfy, où le push n'est qu'un ID et le téléphone va
  chercher le message : un serveur local n'est pas joignable depuis la 4G, et la notification
  serait vide. Ici, elle s'affiche même si le serveur ne répond pas.
- **Aucun serveur ne dépend du relais.** Sans lui (serveur hors ligne, administrateur qui l'a
  coupé, relais en panne), on retombe sur le sondage des ADR-0059 et 0077, qui reste en place.

### 2. Le serveur s'inscrit une fois, puis le relais lie chaque jeton à son serveur

- Au premier envoi, le serveur s'inscrit anonymement : `POST /v1/installations` renvoie
  `{id, secret}`, rangés dans ses réglages. Il n'y a ni compte ni adresse e-mail, et le relais ne
  connaît pas l'adresse du serveur.
- Chaque envoi est signé avec ce secret (HMAC de l'horodatage et du corps). Le relais limite le
  débit par installation (par exemple 60 par minute et 2 000 par jour) et par adresse IP.
- **Un jeton appartient à la première installation qui l'utilise.** Un serveur qui aurait volé des
  jetons ne pourrait donc pas écrire aux téléphones d'un autre serveur. Si un appareil a des
  comptes sur deux serveurs, chacun reçoit un jeton différent (voir §4).
- Quand APNs répond `410` ou que FCM répond `UNREGISTERED`, le relais répond `410` au serveur, et
  celui-ci oublie l'appareil.

### 3. Côté serveur

- **Appareils à prévenir :** une table `push_devices` (session, plateforme, jeton, clé publique,
  types d'évènements acceptés, langue) remplie par `POST /api/me/push-devices`. Elle est vidée à la
  déconnexion de la session. Une capacité `push` dans `/api/ping` indique à l'app que le serveur sait
  pousser.
- **File d'envoi :** les évènements partent d'une file en mémoire, avec quelques nouvelles
  tentatives. Une notification ratée n'est pas grave : le sondage la rattrape, et l'ID de
  l'évènement sert à éviter les doublons dans les registres de l'app (`RequestFeedLedger`,
  `NewEpisodeLedger`).
- **Réglage de l'administrateur :** *Notifications instantanées (relais Onyx)*, avec une phrase qui
  dit ce que le relais voit. L'administrateur peut le couper : son serveur ne contacte alors plus
  personne, et ses utilisateurs gardent le sondage.
- **Langue :** le texte est rédigé par le serveur, dans la langue que l'appareil a déclarée en
  s'inscrivant, comme les messages du serveur de l'ADR-0138. Chaque nouveau texte existe en FR et
  en EN.

### 4. Côté app

- **Android :** `firebase_messaging` fournit le jeton FCM. Les messages sont des messages de
  données (`data`) en priorité haute, qui arrivent même en Doze. Le gestionnaire de fond en Dart
  déchiffre puis affiche par `OnyxNotifications`, avec les canaux existants (`new_requests`, etc.)
  et `NotificationPoster` pour l'affiche. Chaque message reçu en priorité haute affiche une
  notification, comme Android l'exige.
- **iPhone/iPad :** APNs en direct, sans SDK Firebase sur les appareils Apple. Le serveur envoie
  une alerte neutre (« Onyx ») avec `mutable-content: 1`, et une **extension de notification**
  (Notification Service Extension, en Swift) la déchiffre puis remplace le titre et le texte avant
  l'affichage. Elle dispose d'environ 30 s. La clé privée est rangée dans un trousseau partagé
  entre l'app et l'extension. Si le déchiffrement échoue, on affiche un texte neutre. On n'utilise
  pas de push silencieux (`content-available`) : iOS les limite et peut les retarder.
- **Un jeton par compte et par appareil :** sur Android, un jeton par instance Firebase. Sur iOS,
  le jeton APNs est unique pour l'app : le relais lie alors la paire (jeton, installation) et non
  le jeton seul. À vérifier pendant la phase 1.
- **App ouverte :** les notifications du serveur à l'écran ne s'affichent pas (règle de
  l'ADR-0059 : la pastille le dit déjà) et passent par les bannières de l'app. Ensuite, un flux
  d'évènements en attente longue sur le serveur actif, `GET /api/events?since=`, qui généralise
  l'attente des invitations de l'ADR-0148, donnera le même direct dans l'app sur tous les écrans,
  ordinateurs et téléviseurs compris.
- **Réglages :** *Réglages → Cet appareil → Notifications* garde un interrupteur par type
  d'évènement, en FR et EN. Rien ne change pour l'utilisateur : la même notification arrive, mais
  plus tôt.

### 5. Ce qui est poussé

| Évènement | Destinataires | Source sur le serveur |
|---|---|---|
| Nouvelle demande | Comptes `manage_settings` | Webhook OnyxHub `created` |
| Demande acceptée ou refusée | Le demandeur | Webhook `status_changed` |
| Demande disponible | Le demandeur | Webhook `imported` ou indexeur |
| Nouvel épisode d'une série suivie | Les comptes qui la suivent | Indexeur (`has_new_episode`) |
| Demande d'accès au serveur (ADR-0013) | Administrateurs | Route existante |
| Message de l'administrateur (ADR-0069) | Tous les comptes | Route existante |
| Nouvelle connexion au compte | Le compte | Ouverture de session (sécurité) |

Les invitations à une séance (ADR-0148) ne sont pas poussées : leur règle est de n'inviter que les
personnes qui ont l'app ouverte.

### 6. Le relais

- Un binaire Go sans état, sauf une petite base SQLite (installations, jetons liés, compteurs).
  Il est livré en image Docker et vit dans `relay/` du dépôt, ce qui donne un seul langage côté
  serveur.
- Coût : FCM et APNs sont gratuits. FCM accepte par défaut 600 000 messages par minute et par
  projet. Un petit VPS suffit, pour quelques euros par mois.
- **Il n'existe pas de relais auto-hébergé pour l'app officielle.** C'est impossible : les clés
  sont celles de l'éditeur. Un fork qui signe sa propre app peut lancer `relay/` avec ses propres
  clés, comme on peut le faire avec Nextcloud.

## Options écartées

- **Garder seulement le sondage.** Il reste en secours, mais il ne donnera jamais le direct : 15
  minutes au mieux sur Android, sans garantie sur iPhone.
- **Une connexion permanente (WebSocket ou SSE) app fermée.** Impossible sur iOS. Sur Android, il
  faut un service de premier plan avec une notification permanente, ce qui use la batterie et est
  encadré par la Play Store. Une connexion n'a sa place qu'**app ouverte** (§4).
- **Chaque administrateur fournit ses propres clés Firebase ou APNs.** Impossible : les jetons et
  les clés sont liés à l'app de l'éditeur.
- **Le modèle ntfy (push vide, puis le téléphone va chercher).** La notification est vide quand
  le serveur n'est pas joignable depuis le téléphone, ce qui est le cas de tout serveur local hors
  de chez soi.
- **Un service tiers (OneSignal, Pushover, ntfy.sh).** Le contenu ou les métadonnées partent chez
  un tiers, avec des limites et des tarifs qui ne dépendent pas de nous, et parfois une app de
  plus à installer.
- **Web Push.** Il ne vise pas les apps natives. Sur iOS, il ne marche que pour un site installé en
  PWA.
- **UnifiedPush.** Pas par défaut, car il faut installer une app « distributeur » en plus. C'est
  une piste plus tard, pour les Android sans services Google (Huawei, ROM dé-googlisées), qui
  gardent pour l'instant le sondage.

## Conséquences

- **Le projet exploite un service.** S'il tombe, rien ne casse, mais tout le monde revient au
  sondage. Il faut une supervision, au minimum un contrôle de santé.
- **Nouvelles dépendances :** `firebase_messaging` (et `firebase_core`) sur Android avec
  `google-services.json`, `cryptography` en Dart, et une cible d'extension avec un App Group sur
  iOS. Côté magasins : la section « sécurité des données » de Google Play et la politique de
  confidentialité doivent mentionner le jeton de push et le relais.
- **Les appareils Apple relèvent de Fytroz** : extension, droits (entitlements), clé APNs et
  essais sur un vrai iPhone. Tsuky ne lance ni ne publie rien côté Apple.
- **Métadonnées :** le relais voit l'adresse IP du serveur, l'heure et le volume des envois à
  chaque appareil. C'est le même compromis que Nextcloud et Bitwarden, et il est écrit dans le
  réglage de l'administrateur.
- **Les serveurs anciens** (sans la capacité `push`) restent sur le sondage, sans rien changer.

## Phases

1. **Relais et Android, pour les demandes :** `relay/`, inscription du serveur, `push_devices`,
   les trois évènements de demande, et sur Android la réception, le déchiffrement et
   l'affichage. Une version de test (niveau 3) depuis `tsuky`.
2. **iPhone/iPad (Fytroz) :** extension de notification, APNs dans le relais, trousseau partagé.
3. **Les autres évènements** (épisodes, accès, message, connexion), un interrupteur par type, et
   le flux `GET /api/events` app ouverte.
4. **Plus tard, si on le demande :** UnifiedPush pour les Android sans Google.

## Questions ouvertes

1. **Où vit le relais, et sous quel nom de domaine ?** Par exemple `push.<domaine d'Onyx>`, sur
   le même hébergement que `onyx.tsuky.ovh` ou sur un VPS à part. Le nom définitif de l'app n'est
   pas encore choisi (store-readiness), donc le domaine doit pouvoir changer : le serveur lit
   l'adresse du relais dans un réglage, avec une valeur par défaut.
2. **Relais allumé par défaut pour les nouveaux serveurs ?** Proposition : oui, avec la phrase
   d'explication et l'interrupteur dans l'administration.
3. **Gratuit pour tous ?** Proposition : oui. Les notifications marchent déjà gratuitement (par
   sondage), et on ne fait pas payer ce qui est gratuit dans une version stable. Le coût est
   négligeable. Le choix revient à Mathis.

## Sources

- Nextcloud, proxy de push chiffré : <https://nextcloud.com/blog/nextclouds-push-notifications-for-ios-and-android/>
- ntfy, `upstream-base-url` et `poll_request` pour iOS : <https://docs.ntfy.sh/config/>, <https://docs.ntfy.sh/known-issues/>
- Bitwarden, relais de push pour l'auto-hébergement : <https://bitwarden.com/help/configure-push-relay/>
- Home Assistant, limite du relais et Local Push : <https://companion.home-assistant.io/docs/notifications/notification-details>
- Apple, modifier une notification reçue (extension, `mutable-content`) : <https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications>
- FCM, limites et quotas : <https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas>
- UnifiedPush, bilan à cinq ans : <https://f-droid.org/fr/2026/01/08/unifiedpush-5-years.html>
