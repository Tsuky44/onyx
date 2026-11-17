# ADR-0138 — Les messages du serveur suivent la langue de la requête

- **Statut :** accepté. Le Go est testé (`server/i18n`, `handlers/json_errors_language_test.go`) ;
  **rien n'a été essayé avec une app réglée en anglais contre un vrai serveur**.
- **Date :** 2026-11-17
- **Portée :** `server/i18n/`, `server/handlers/json_errors.go`, `server/handlers/mediahub.go`
  (`writeMediaHubError`), `server/main.go` (le middleware), les handlers qui écrivent un message,
  `app/lib/providers/home_provider.dart` et `app/lib/screens/home/home_screen.dart`.

## Contexte

L'ADR-0047 a traduit l'interface de l'app avec le texte français pour clé, et l'ADR-0049 a fait
suivre la langue de l'interface aux fiches. Les messages d'erreur du serveur, eux, restaient en
français : l'app affiche tel quel le champ `error` des réponses JSON, si bien qu'une personne qui a
réglé l'app en anglais lisait « Vous n'avez pas le droit de faire cela » au milieu d'un écran
anglais. L'ADR-0047 avait écarté « traduire côté serveur » parce que ces messages étaient alors
« une petite partie de ce que l'utilisateur lit ». Ils sont maintenant la dernière.

Le serveur compte ~540 appels à `writeJSONError(w, status, message)` et 14 à `writeMediaHubError`,
sans la requête sous la main. Il lit déjà `Accept-Language` pour les fiches (`medialang`), et l'app
l'envoie sur chaque requête.

## Décision

**Même principe que l'app : la clé est le texte français, chaque autre langue est un dictionnaire
français → langue.**

1. Le paquet `server/i18n` porte `T(lang, fr, args…)`, `FromRequest` et `FromHeader`. `en` est une
   `map[string]string` dans `en.go`, triée. Une clé absente d'un dictionnaire, ou une langue sans
   dictionnaire, rend le français. `{0}`, `{1}`… sont les valeurs de la phrase : la traduction les
   place où sa grammaire les veut. **Ajouter l'espagnol ou l'allemand** : un fichier `es.go` /
   `de.go` avec sa map, et une ligne dans `dictionaries`.
2. **La langue des messages n'est pas celle des fiches.** `i18n.FromHeader` répond « français »
   quand l'en-tête manque ou ne cite aucune langue connue : une app d'avant ce réglage reçoit les
   messages qu'elle recevait, même si les métadonnées du serveur sont en anglais.
3. **Le signal passe par la réponse, pas par la signature.** `i18n.Middleware`, monté devant le
   routeur dans `main.go`, pose `Content-Language` sur les réponses `/api/`.
   `writeJSONError(w, status, message, args…)` et `writeMediaHubError` lisent ce en-tête
   (`i18n.Respond`). Les 550 appels existants ne changent pas ; un handler appelé sans le middleware
   (un test) répond en français.
4. **Un message avec des valeurs est une phrase à emplacements**, jamais un `fmt.Sprintf` ni une
   concaténation : `writeJSONError(w, 400, "Donnez un nom ({0} caractères au plus)", n)`.
5. **Une erreur qui voyage** (un validateur, un client Emby) est une `i18n.Error` (`i18n.Errorf`),
   que `writeJSONFailure` traduit. Un texte rangé dans une variable avant d'arriver au handler est
   marqué par `i18n.Key("…")`, qui rend son argument et laisse le test de couverture le lire.
6. **Ce qui reste brut.** L'erreur technique d'un système qu'Onyx ne contrôle pas (le texte d'un
   autre serveur Onyx, d'un MediaHub, d'Emby) est passée en argument derrière une phrase traduite
   (« L'autre serveur a répondu : {0} »). Les trois codes de protocole entre serveurs
   (`link_unknown`, `peer_unknown`, `peer_not_approved`) ne sont pas des phrases : elles se lisent
   par l'autre serveur, pas par une personne.
7. **Les messages anglais d'origine passent en français.** Une centaine de handlers répondaient des
   phrases anglaises (« Invalid media ID », « Internal server error ») que même l'app en français
   affichait. Elles deviennent des clés françaises, avec leur anglais dans le dictionnaire.
8. **Garde-fou.** `server/i18n/coverage_test.go` lit tout `server/` (hors tests) avec `go/ast`,
   extrait chaque phrase passée à `writeJSONError`, `writeMediaHubError`, `i18n.T`, `i18n.Respond`,
   `i18n.Key` et `i18n.Errorf` (littéral, constante, ou littéraux collés par `+`), et échoue quand une
   langue n'a pas sa traduction, quand le dictionnaire garde une entrée que plus aucun message
   n'utilise, ou quand une phrase est construite par `fmt.Sprintf` / concaténation.
9. **Côté app, le couplage au texte du serveur disparaît.** `home_screen.dart` testait
   `msg.startsWith('Re-détection') || msg.startsWith('Scan')` pour recharger la bibliothèque : le
   texte vient de `tr()`, donc il change avec la langue, et en anglais le rechargement ne se faisait
   plus. `HomeProvider.consumeCompletion()` rend un `HomeCompletion` dont le champ
   `refreshesLibrary` porte la décision.

## Conséquences

- Une nouvelle phrase d'erreur s'écrit en français dans le handler **et** s'ajoute à `en.go` :
  `go test ./i18n` le dit, avec la phrase manquante.
- Changer le français d'une phrase demande de changer sa clé dans chaque dictionnaire ; le test
  signale l'ancienne entrée devenue morte.
- Content-Language est posé sur toute réponse `/api/`, y compris les réponses qui ne contiennent
  aucun message. Les médias, les segments HLS et la SPA ne sont pas touchés.
- **Reste en français**, volontairement : les `http.Error` en texte brut (une soixantaine,
  « Unauthorized », les messages du lecteur de secours), que l'app ne lit pas ; `last_error`, la
  dernière erreur d'une synchronisation Emby ou d'un lien fédéré, qui est écrite dans la base au
  moment de l'échec ; les messages de réussite des routes d'administration de l'indexeur, que l'app
  ne montre pas ; le journal du serveur.
- Les messages de `Notes` / `Message` du test de liaison MediaHub (`mediahub_link.go`) passent par
  `i18n.T` avec la langue de la requête, puisqu'ils s'affichent dans les réglages.
