# Contrat Seerr (Overseerr, Jellyseerr)

Ce qu'Onyx lit et écrit chez Overseerr et Jellyseerr (ADR-0136). Les deux partagent l'API de Seerr,
sous `/api/v1` ; ces fichiers en sont des exemples, écrits d'après leur code (`server/routes/`,
`server/entity/`, `server/lib/permissions.ts`) et réduits aux champs qu'Onyx lit.

Les tests de `server/mediahub/seerr_test.go` et de `server/handlers/seerr_test.go` montent un faux
Seerr qui sert ces fichiers : changer ce qu'Onyx y lit, c'est d'abord changer l'exemple.

| Fichier | Appel |
|---|---|
| `status.json` | `GET /status` (public) |
| `settings_public.json` | `GET /settings/public` (public) |
| `auth_me.json` | `GET /auth/me` : le compte de la clé |
| `users.json` | `GET /user?take=&skip=` |
| `requests.json` | `GET /request?take=&skip=&sort=added&filter=all[&requestedBy=]` |
| `movie.json` | `GET /movie/603` |
| `tv.json` | `GET /tv/1399` |
| `request_create.json` | corps de `POST /request` |
| `request_refused.json` | un refus (`403`, `409`) : `{ message }` en anglais |

Chaque appel porte `X-Api-Key`, et `X-Api-User: <id>` quand Onyx agit au nom d'un compte Seerr.
