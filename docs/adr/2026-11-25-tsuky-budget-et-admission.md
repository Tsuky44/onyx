# Le serveur compte un budget, pas des sessions, et l'Auto se dit avec `auto=1`

- **Statut :** accepté, phase 3 du plan [transcodage adaptatif](../transcodage-adaptatif.md).
  **Écrit sans les machines** : les tests couvrent le budget, l'admission, l'audio et les aperçus
  avec des profils fictifs ; aucune admission n'a été vue sur la prod, l'i7 de fytroz ou un petit
  serveur.
- **Date :** 2026-11-25
- **Portée :** `server/streaming/capacity/budget.go` (nouveau) ; dans `server/streaming/` :
  `admission.go`, `session_budget.go`, `start_options.go`, `start_response.go`,
  `audio_renditions.go`, `previews_budget.go` (nouveaux), `handler.go`, `handler_pipeline.go`,
  `manager.go`, `session.go`, `workspace.go`, `previews.go`, `probe.go`, `ffmpeg.go` ;
  `server/handlers/ping.go`, `contract/hls_start.json` (nouveau), `contract/ping.json`,
  `contract/media_tracks.json` ; `app/lib/services/hls_session.dart`,
  `app/lib/models/server_capabilities.dart`, `app/test/api_contract_test.dart`.
- **Contredit l'ADR-0033** (§ nombre de sessions) : `MAX_TRANSCODES` ne borne plus le serveur par
  défaut une fois le profil prêt. On compte ce que les sessions coûtent, pas combien elles sont. Le
  plafond reste un forçage, appliqué quand l'opérateur le pose.
- **Prolonge** l'ADR [profil matériel et planificateur](2026-11-25-tsuky-profil-materiel-et-planificateur.md),
  dont la charge (`capacity.Load`) était nulle, et l'ADR
  [session remplacée gelée](2026-11-25-tsuky-session-remplacee-gelee-et-threads-reels.md) : le gel
  rend maintenant la réservation.

## Contexte

`max(cœurs/2, 4)` sessions : une recopie, qui ne coûte presque rien, pesait autant qu'un 4K Dolby
Vision qui prend tous les cœurs d'un petit serveur. Sur 4 cœurs, quatre 4K HDR10 étaient admis
alors qu'un seul tient 1,1×. Le planificateur de la phase 2 sait ce que coûte une recette, mais il
la jugeait sur une machine vide.

Le menu Qualité reste au spectateur (§1 du plan) : un barreau choisi à la main est toujours livré.
Or le serveur ne savait pas si le barreau venait d'un choix ou de l'Auto.

## Décision

### 1. Un budget par ressource

`capacity.Budget` tient, par session, le coût prévu de sa recette (`Pipeline.Cost`, à la vitesse de
lecture) sur les quatre ressources du planificateur, plus l'audio (0,04 cœur par piste, *estimé*).
Une recopie réserve 0,05 cœur (*estimé*). C'est le coût à 1× : une session va plus vite tant
qu'elle prend son avance, puis le bridage la ramène à 1× en moyenne.

- **Réserver :** dès l'admission, sous un verrou du gestionnaire (`admitAndReserve`), pour que deux
  `/start` simultanés ne lisent pas la même charge. `CreateSession` reprend la réservation sous le
  même identifiant. Une session en attente (`standby`) réserve aussi : son FFmpeg encode déjà.
- **Rendre :** au gel (`Freeze`, une session remplacée), à la sortie de FFmpeg (film fini ou
  session morte), à la destruction. `Release` est sans effet la deuxième fois.
- **Charger :** `PlanPipeline` reçoit la charge réservée par les autres, sans les sessions du
  ticket qui demande, puisque la nouvelle va les remplacer. C'est vrai aussi d'une demande
  `standby` : l'ancienne session tourne encore jusqu'au changement de source, mais seulement le
  temps de la bascule.
- **Pour les phases 4 et 5 :** `SessionManager.Budget()`, puis `Budget.Margin(profil, ticket)` pour
  la marge du moment, `Budget.Load(ticket)` et `capacity.SpeedUnder(coût, profil, charge)` pour la
  tenue d'un barreau.

### 2. L'admission

Le planificateur prend déjà, au barreau demandé, la recette la moins chère quand la meilleure ne
tient pas. Si elle tient 1,3× (critère 1 du plan), la session est admise. Sinon :

- **avec `auto=1`**, le serveur descend dans le menu de la source, dans l'ordre du débit
  (`QualityLadderFor`), et sert le premier barreau qui tient 1,3×. La descente ne demande donc
  jamais plus à la ligne que ce que l'Auto avait choisi. La réponse porte `quality` (le servi),
  `requested_quality` (le demandé) et `capacity_warning: "degraded"`. Si rien ne tient 1,3×, le
  plus rapide est servi, s'il suit la lecture ;
- **sans `auto=1`** (choix manuel, et tous les clients déjà installés), le barreau demandé est
  servi tel quel, avec `capacity_warning: "too_heavy"` ;
- **la limite dure** : aucun barreau du menu ne suivrait la lecture (moins de 1×). `/start` répond
  alors 503 `{"error": "server_busy", "reason": "…"}` avec `Retry-After: 15`, en Auto comme en
  manuel. Ouvrir quand même ferait saccader toutes les sessions en cours, pas seulement la nouvelle.

Sans profil prêt, la vitesse prévue est infinie : le barreau demandé est servi, et seul le plafond
de sessions d'avant compte (`sessionCap`). Une fois le profil prêt, `MAX_TRANSCODES` ne s'applique
que s'il est posé.

**Pourquoi `auto=1` et pas `manual=1`** (décision §0.5) : un paramètre qui dit l'Auto laisse les
clients actuels, qui n'envoient rien, dans le cas sûr. Avec `manual=1`, un client déjà installé
aurait vu sa qualité baisser sans l'avoir demandé. La capacité `transcode_capacity` de `/api/ping`
dit au client que le serveur comprend `auto=1`. Le modèle Dart lit les trois champs ; aucune UI ne
les montre encore (phase 4).

### 3. Les pistes audio

Une petite machine publie deux pistes : la choisie et la VO. Une grosse en publie jusqu'à huit, comme
avant (décision §0.4). **Petite** veut dire : 4 cœurs ou moins, et aucun circuit utilisable (ni
encodeur du circuit qui a passé son essai, ni libplacebo sur un circuit). Le seuil vient de la
machine de fytroz : sur 4 cœurs, un 4K HDR10 vers 1080p prend 3,44 cœurs et tient 1,1× (*mesuré*).
Les quelques dixièmes de cœur de huit pistes TrueHD y séparent 1,1× de 1,0×. À 8 cœurs, ou avec un
circuit qui prend l'image, ils ne pèsent plus. La VO est la piste que ffprobe marque `original`,
sinon celle marquée par défaut, sinon la première. La sonde lit maintenant cette disposition
(`AudioStreamInfo.Original`). `probeVersion` n'est pas relevé : relancer la sonde de chaque fichier
coûterait plus que de retomber sur la piste par défaut pour les sondes déjà enregistrées. Un
changement vers une langue non publiée relance une session : le serveur publie toujours la piste
demandée, et le client recharge la session quand la piste manque à `audio_map`.

### 4. Les aperçus

La passe de fond des aperçus garde sa priorité basse, son thread unique et le périphérique Vulkan
des sessions (fytroz). Elle n'extrait une image que si le budget laisse un cœur libre, et elle se met
en pause entre deux images dès qu'une session le réserve. Une image prend 40 à 170 ms, donc la
pause est presque immédiate. Les survols ne sont pas concernés : le spectateur les attend.

### 5. Le disque

`HLS_MIN_FREE_MB` reste tel quel. Le budget disque par débit est reporté, voir le plan.

### Écarté

- **Juger la nouvelle session contre une machine vide et laisser la rétroaction corriger.** C'est la
  saturation que le plan veut supprimer : la seconde session ralentit la première, et aucune des
  deux ne reprend d'avance.
- **Refuser (503) en manuel dès que le barreau ne tient pas.** Ce serait reprendre le choix au
  spectateur. Le 503 ne sert qu'à ce qui ferait tomber tout le monde.
- **Descendre au même débit plutôt que dans l'ordre du menu.** Le coût suit les pixels, pas le
  débit. L'ordre du menu donne justement, au même débit, le barreau aux lignes moins nombreuses
  (`1080p` puis `720p-6m`).

## Conséquences

- Sans `MAX_TRANSCODES`, un serveur avec un profil admet autant de recopies que son budget en
  permet (une vingtaine par cœur). Le disque et la ligne les bornent alors. `MAX_TRANSCODES` reste
  le garde-fou d'un opérateur qui veut un plafond.
- La réservation suppose qu'une session tourne en moyenne à 1×. Un lecteur en pause garde sa
  réservation alors que son FFmpeg est arrêté par le bridage : le budget est prudent, jamais
  optimiste.
- Les coûts de l'audio et de la recopie sont estimés. La rétroaction (phase 5) corrigera le profil,
  mais pas ces deux constantes.
- Le corps du 503 de saturation est maintenant du JSON. Aucun client ne le lisait.

## À vérifier sur une vraie machine

1. Une machine de 4 cœurs sans GPU : deux lecteurs en Auto sur un 4K HDR10. Le second doit voir
   `HLS start: media N: … demandé, … servi (degraded, …)` ou un 503 `server_busy`, et le premier ne
   doit pas passer sous 1× (`Session …: … encodé à N× la vitesse de lecture`).
2. La même chose en manuel : le second est servi tel quel, `too_heavy` au journal.
3. Les aperçus en pause pendant une session lourde (`previews: media N: en pause`), puis la reprise.
4. Un fichier à huit pistes sur la même machine : `renditions=[…]` ne liste que deux pistes.
