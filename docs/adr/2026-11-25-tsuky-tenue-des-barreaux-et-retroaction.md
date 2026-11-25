# Le serveur dit ce que chaque barreau tiendra, apprend de ses sessions, et suggère ; le client décide

- **Statut :** accepté, phases 4 (côté serveur) et 5 du plan
  [transcodage adaptatif](../transcodage-adaptatif.md). **Écrit sans les machines** : les tests
  couvrent la tenue, la correction, la mémoire des fichiers lents, la suggestion et le retrait avec
  des profils fictifs (Xeon, 4 cœurs sans GPU, i7 + iGPU) ; aucune session réelle n'a nourri la
  correction.
- **Date :** 2026-11-25
- **Portée :** `server/streaming/capacity/` : `correction.go` (nouveau), `planner.go`, `profile.go`,
  `registry.go` ; `server/streaming/` : `ladder_fit.go`, `session_pace.go`, `session_feedback.go`,
  `lighter_recipes.go`, `suggest_quality.go`, `recipe_retire.go`, `profile_publish.go`,
  `start_session.go` (nouveaux), `quality.go`, `session.go`, `handler.go`, `handler_media.go`,
  `handler_pipeline.go`, `start_options.go`, `start_response.go`, `admission.go`,
  `capacity_profile.go`, `capacity_candidates.go`, `hardware_filters.go`, `vulkan_device.go` ;
  `server/handlers/playback.go`, `server/main.go` ; `contract/media_tracks.json`,
  `contract/hls_health.json` (nouveau) ; `app/lib/models/media_tracks.dart`,
  `app/lib/services/hls_session.dart`, `app/lib/services/api/playback.dart`,
  `app/test/api_contract_test.dart`.
- **Prolonge l'ADR-0056** (qualité automatique) : quand c'est le serveur qui ne suit pas, le client
  ne faisait rien, à raison, parce que descendre en débit ne soulage pas un encodeur. Le serveur
  donne maintenant une suggestion ; **le client décide**. Prolonge aussi les ADR
  [profil matériel et planificateur](2026-11-25-tsuky-profil-materiel-et-planificateur.md) (le
  banc est corrigé par la vitesse réelle) et [budget et admission](2026-11-25-tsuky-budget-et-admission.md)
  (la tenue d'un barreau est celle que l'admission calculerait).

## Contexte

Après la phase 3, le serveur sait ce que coûte une recette et ce qui reste de sa machine, mais il
ne le dit qu'à `/start`, et il ne vérifie jamais sa prévision. Trois choses la rendent optimiste :
la source de synthèse du banc, plus facile qu'un vrai film ; une machine qui chauffe (l'i7 de
fytroz à 99 °C) ; et l'hypothèse qu'une session prend tous les cœurs libres, fausse sur un Xeon à
deux sockets. Une session sous 1× ne prend jamais son avance et sature le serveur jusqu'à la fin
(critère 2 du plan).

## Décision

### 1. La tenue des barreaux dans `/tracks`

`QualityTier` gagne `fit` : `ok` (au moins 1,5×), `limite` (1 à 1,5×) ou `trop_lourd` (sous 1×),
le vocabulaire de `capacity.Verdict`. Elle est calculée par `Handler.QualityLadder`, au même
endroit que l'admission (`startInputs.tryRung`) : décision de recopie avec les capacités que le
client déclare (les paramètres de `/start`, lus aussi par `/tracks`), recette, charge du moment,
facteur du fichier. Un barreau recopié est `ok`. Sans profil, `fit` est absent. **Aucun barreau
n'est retiré.** `handlers` n'importe que `streaming` : le gestionnaire y est branché par une
variable (`handlers.QualityLadder`, comme `ActiveTranscodes`).

La charge est celle de toutes les sessions, celles du spectateur comprises : `/tracks` n'a pas de
ticket, et le lecteur le lit avant d'ouvrir sa session.

**Pas de capacité dans `/api/ping`.** `fit` et `suggested_quality` sont des champs optionnels dont
l'absence veut déjà dire « rien à dire » : un serveur d'avant, et un serveur dont le profil n'est
pas prêt, se lisent de la même façon, et le client doit traiter les deux. `transcode_capacity`
reste ce qui dit que `auto=1` est compris. Une capacité de plus n'apprendrait rien au client.

### 2. La correction du profil

Chaque session rapporte sa vitesse à plein régime (à la première pause du bridage, ou à 20 s sous
1×) et, à sa fin, son temps CPU. Le rapport réel/banc, **borné entre 0,5 et 2,5**, entre dans une
moyenne lissée (**α = 0,25**) par classe de recette, elle-même **bornée entre 0,5 et 3**. La
classe : décodage (circuit ou processeur, flux léger ou lourd), hauteur produite, tone mapping et
son périphérique, encodeur, et un drapeau pour les filtres logiciels que le banc ne mesure pas.
Le planificateur multiplie les coûts de la classe par ce facteur ; la réservation du budget aussi.

- **Pourquoi ces bornes.** Une session aberrante (un fichier cassé, un partage réseau qui cale)
  donnerait un rapport de 10 ou 20 ; bornée, elle déplace une classe neutre jusqu'à 1,375 au plus.
  Il faut trois ou quatre sessions concordantes pour faire l'essentiel du chemin. Au-delà de ×3,
  ce n'est plus corriger : c'est remesurer.
- **Ce qui n'est pas compté.** Une session de moins de vingt secondes de film (un saut suivi d'un
  autre), une session gelée (son temps gelé n'est pas une vitesse), une recopie, une vitesse
  prévue au-delà de 4× (un 360p bute sur la lecture du fichier, pas sur les cœurs), le temps CPU
  d'une recette du circuit (moins d'un quart de cœur prévu : dominé par le démarrage et l'audio).
- **Un seul facteur pour la vitesse et le budget.** Sur le Xeon, une session va moins vite que
  prévu sans brûler plus : le facteur suit le plus prudent des deux signaux. La fin n'ajoute le
  temps CPU que s'il dit plus lourd que la vitesse déjà rapportée. Le budget peut donc réserver un
  peu plus que le réel : prudent, jamais optimiste, comme en phase 3.
- **Le preset n'est pas dans la classe.** Ce qui rend le banc optimiste pèse sur tous les presets
  d'un encodeur ; une correction par preset laissait le planificateur fuir vers un preset jamais
  observé, prévu aussi faux.
- **Persistance.** `Profile.Corrections` est écrit avec le profil. `Remeasure()` et toute autre
  empreinte construisent un profil neuf, donc sans correction.

### 3. Un fichier qui fait ramer une session

Une session qui passe **20 s sous 1×**, mesurée sur une fenêtre glissante hors des dix premières
secondes et hors pause ou gel, laisse au fichier un facteur `vitesse prévue / vitesse vue` (borné
à 4), pendant **20 minutes** (`ttlcache`, 256 fichiers). Le planificateur multiplie les coûts de ce
fichier par ce facteur (`capacity.Job.Slowdown`), et sa règle donne d'elle-même l'ordre du plan :
un preset plus rapide au même barreau s'il tient, sinon une vitesse sous 1,3× qui fait descendre
l'Auto à l'admission ; un choix manuel est servi tel quel, avec `too_heavy`.

Un plancher de preset et un plafond de vitesse séparés ont été écartés : le facteur unique dit la
même chose, et il vaut aussi pour la tenue affichée et pour la suggestion.

### 4. `suggested_quality` dans `/health`

- **Descente** (session sous 1× depuis 20 s) : le plus haut barreau, du barreau en cours vers le
  bas, qui tient 1,3× sous la charge sans la session elle-même. Un barreau qui referait la même
  image avec la même recette (le barreau en cours, ou un autre débit à la même hauteur) est sauté :
  la session vient de montrer qu'elle ne tient pas, quoi qu'en dise le modèle. La suggestion peut
  donc être **le barreau en cours** quand une recette plus légère y tient : le rouvrir ne change
  rien à ce que le spectateur a choisi, ce qui vaut aussi en manuel. À défaut de 1,3×, le plus
  rapide s'il suit la lecture.
- **Remontée** : le plus haut barreau `ok` au-dessus du barreau en cours, au plus le **plafond** de
  la session : le barreau demandé si l'Auto a été descendu à l'admission, hérité de la session
  remplacée quand la nouvelle s'ouvre au même barreau (un saut) ou au barreau suggéré (l'Auto a
  suivi) ; sinon le barreau servi, donc pas de remontée au-dessus d'un choix. Jamais au-dessus du
  natif de la source.
- **Hystérésis** : deux seuils (descente sous 1× vu, remontée à 1,5× prévu) ; une remontée attend
  que la session tourne depuis 40 s, puis que le même barreau reste `ok` 30 s sans interruption ;
  le facteur d'un fichier lent rend la remontée vers le barreau qui a ramé bien plus exigeante
  jusqu'à son expiration.
- **Absent** sans profil, sans rien à suggérer, pour une session gelée.

Le modèle Dart lit `/health` par `HlsSessionHealth` (au lieu d'un *record*), avec
`suggestedQuality`. Aucune UI ne s'en sert encore.

### 5. Le retrait unifié

`noteHardwareSessionDied` et `noteVulkanSessionDied` passent par un seul `retireRecipe`, qui
choisit la recette fautive la plus précise d'une session morte avant son premier segment (la
chaîne VAAPI, puis libplacebo sur le circuit, puis un encodeur du circuit choisi par la mesure),
bascule l'état en mémoire, retire la recette du registre et publie le profil. Chaque retrait est
gardé avec l'erreur de FFmpeg dans `TrialResult.Withdrawals`, lisible par `Profile.Withdrawn()`
pour la future page d'administration. Le comportement de fytroz est inchangé : ses tests passent
sans modification. Nouveau : un encodeur du circuit que la mesure avait retenu (sans
`VIDEO_ENCODER`) sort des candidats ; un encodeur forcé n'a pas d'essai à son nom et n'est jamais
retiré, comme avant.

## Conséquences

- Le menu peut dire « peut saccader » et l'Auto peut ouvrir au bon barreau dès que le client lira
  `fit` ; un client actuel ignore le champ.
- Une prévision fausse se corrige d'elle-même : immédiatement pour le fichier, en quelques sessions
  pour la classe. Une correction apprise dans une période de forte chaleur reste jusqu'à ce que des
  sessions plus rapides la ramènent : la moyenne redescend aussi vite qu'elle est montée.
- Une session qui meurt pour une raison propre au fichier (fichier cassé) avant son premier segment
  retire un encodeur du circuit pour tout le serveur, jusqu'à la remesure : c'est déjà le cas des
  deux règles de fytroz, étendu à l'encodeur.
- `handler.go` passe de 693 à 663 lignes (préparation de la session et réponse de `/start`
  extraites).

## Question ouverte pour Tsuky

Le critère 4 du plan (moins de 0,2 cœur par session sur un iGPU) et la règle « la meilleure image
quand il y a de la marge » se contredisent au repos : un i7 libre garde x264 `veryfast`, plusieurs
cœurs par session, parce que le circuit ne gagne que faute de marge. La correction ne change rien à
cela. Faut-il épargner le processeur même au repos (le circuit dès qu'il tient 1,5×), au prix de
l'image, ou garder la règle et lire le critère 4 « sous charge » ?

## À vérifier sur une vraie machine

1. Une session lente (4 cœurs, 4K HDR10 en 1080p) : `Session … sous la vitesse de lecture depuis
   20s`, puis `Streaming: correction de hevc10/cpu|1080p|zscale|libx264 : ×1.00 → ×1.…`, puis
   `/health` qui rend `suggested_quality`, et la session suivante du même fichier en preset plus
   rapide (`recette …, fichier lent ×…`).
2. `/api/media/:id/tracks` sur la même machine : `2160p` `trop_lourd`, `1080p` `limite`, `720p`
   `ok` (prévu par les tests ; à comparer à la vitesse réelle).
3. Le Xeon de la prod chargé : la correction de la classe 2160p monte-t-elle au-delà de ×1,5 (les
   seize threads de x264 sur trente-deux cœurs) ?
4. `capacity-profile.json` après quelques soirées : des `corrections` plausibles (0,8 à 2), et
   aucune à la borne.
