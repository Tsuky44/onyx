# ADR 2026-11-24 (fytroz) : la version d'une publication part de ce qui est déjà sorti

- **Statut :** accepté. Le calcul est testé (`app/test/release_version_resolution_test.dart`) ;
  **aucun run de `release.yml` ni de `tvos.yml` n'a encore tourné avec lui.**
- **Date :** 2026-11-24
- **Portée :** `scripts/ci/resolve-version.sh` (nouveau), `.github/workflows/release.yml` (job
  `prepare`), `.github/workflows/tvos.yml` (étapes de version, droit `contents: write`),
  `docs/release-ci.md`.

## Contexte

Une publication globale (`release.yml`) calculait déjà sa version seule, à partir du dernier tag
`vX.Y.Z`, et toutes les plateformes la portaient. L'Apple TV peut aussi sortir seule sur TestFlight
(`tvos.yml`), sans tag ni Release : elle reprenait la version du dernier tag, avec un horodatage
pour numéro de build.

Le 2026-11-24, ce montage a cédé en deux temps :

- **Apple a refusé le build.** La `1.2.0` avait été approuvée, et App Store Connect ferme une
  version approuvée (« train version '1.2.0' is closed for new build submissions »). Il a fallu
  choisir la `1.2.1` à la main.
- **Cette `1.2.1` n'était notée nulle part.** La publication globale suivante, calculée depuis
  `v1.2.0`, aurait été la `1.2.1` elle aussi, avec le numéro du run pour numéro de build : plus
  petit que l'horodatage déjà reçu, donc refusé pour l'Apple TV. Il aurait fallu s'en souvenir et
  taper `1.2.2`.

## Décision

1. **Une plateforme sortie seule note sa version** par un tag `build/<plateforme>/X.Y.Z`, poussé
   après l'envoi réussi (`resolve-version.sh record`). Ni `v*` (qui déclenche `release.yml`), ni
   `tvos-*` (qui déclenche `tvos.yml`).
2. **Une publication globale part de la plus haute version connue**, tags `vX.Y.Z` et notes de
   plateforme confondus, et toutes les plateformes s'y alignent : `v1.2.0` et Apple TV en `1.2.1`
   donnent la `1.2.2` partout.
3. **Une plateforme seule ne reprend jamais la version du dernier tag** : elle en ouvre une
   au-dessus, puis y reste tant qu'aucune publication globale n'est passée.
4. **Un seul calcul**, dans `scripts/ci/resolve-version.sh`, appelé par les deux workflows.

### Écarté

- **Une version par plateforme** (le PC en `1.2.1`, l'Apple TV en `1.2.2`). Une publication n'a
  qu'un tag, qu'une image et qu'une Release, et le serveur lit la version dans le nom des
  installeurs : il faudrait une version par artefact partout. S'aligner sur la plus haute donne le
  même résultat visible, sans rien changer d'autre.
- **Demander la version à App Store Connect.** C'est la source exacte, mais il faut signer un jeton
  et lire une API de plus dans un runner, sans moyen de l'essayer ici.
- **Donner un horodatage aux builds Apple de `release.yml`.** L'envoi ne serait plus refusé, mais
  la publication globale reprendrait le numéro de l'Apple TV au lieu de passer au-dessus.

## Conséquences

- Sans plateforme sortie seule, rien ne change : la version part du dernier tag, comme avant.
- Chaque build d'Apple TV seul après une publication globale consomme un numéro de version.
- `tvos.yml` pousse un tag : il lui faut `contents: write`. Si le tag ne part pas, le run reste
  vert (le build est bien sur TestFlight) et dit en avertissement la commande à lancer.
- Le build `1.2.1` du 2026-11-24 a été lancé avant ce changement : sa note `build/tvos/1.2.1` se
  pose à la main.
