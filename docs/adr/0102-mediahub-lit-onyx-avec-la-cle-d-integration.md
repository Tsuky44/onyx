# ADR-0102 — MediaHub lit Onyx avec la clé d'intégration

- **Statut :** accepté
- **Date :** 2026-11-02
- **Portée :** `server/handlers/mediahub_directory.go`, les routes
  `GET /api/integrations/mediahub/users`, `/movies`, `/shows`, `/counts`, `GET|PUT /api/integrations/mediahub/link`,
  la capacité `mediahub_directory`, `contract/mediahub/onyx_integration_*.json`. Prolonge les
  ADR-0089 et ADR-0090.

## Contexte

Onyx parle déjà à MediaHub avec la seule clé d'intégration (ADR-0089). Dans l'autre sens, MediaHub
ouvrait une session d'administrateur Onyx (nom, mot de passe, OTP) et la gardait dans ses réglages
pour lister les comptes, lire la bibliothèque et écrire son adresse dans `PUT /api/settings`.

Cette session expirait après 90 jours d'inactivité, cassait l'import quand l'administrateur changeait
de mot de passe, et ouvrait à MediaHub tout ce qu'un administrateur peut faire : supprimer un compte,
changer la politique OTP, repointer une bibliothèque.

## Décision

- **La clé suffit.** Elle fait déjà agir MediaHub au nom de chaque compte. Les quatre routes
  ci-dessus la vérifient (`RequireMediaHubKey`, temps constant via `mediahub.VerifyKey`) et ne
  rendent que ce que MediaHub lit : les comptes sans gabarit d'invitation ni état OTP, la
  bibliothèque et ses totaux, l'état de la liaison.
- **La progression du compte qui regarde.** `X-Player-Id` (ADR-0090) nomme le compte Onyx lié à
  l'utilisateur MediaHub : `/movies` et `/shows` portent alors sa progression (pastilles « vu »,
  épisodes restants). Sans en-tête ou avec un id inconnu, l'utilisateur 0 : aucune progression,
  jamais d'erreur. La clé fait déjà agir MediaHub au nom de n'importe quel compte.
- **Pas d'écriture large.** `PUT /link` n'écrit que l'adresse de MediaHub et, pour une rotation,
  une nouvelle clé de 32 caractères au moins. Présenter l'actuelle suffit, comme pour un mot de
  passe. Rien d'autre des réglages ne s'ouvre à la clé.
- **La première clé se pose à la main**, d'un seul côté puis copiée de l'autre (réglages d'Onyx ou
  de MediaHub). Un appairage automatique demanderait une route publique de plus pour un geste fait
  une seule fois.

## Conséquences

- MediaHub n'a plus de compte de service Onyx : `onyx_service_token` disparaît de ses réglages.
- Une fuite de la clé expose la liste des comptes (noms et droits) et le catalogue, plus ce qu'elle
  exposait déjà. Elle reste un secret d'administrateur.
- Les routes sont limitées comme un sondage (`PollLimiter`) : un balayage de clés ne passe pas.
