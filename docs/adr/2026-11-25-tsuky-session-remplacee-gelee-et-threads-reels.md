# Une session remplacée est gelée tout de suite, et les threads suivent les cœurs réels

- **Statut :** accepté (lot rapide du plan [transcodage adaptatif](../transcodage-adaptatif.md)).
  Non vu sur une machine de prod : les tests le couvrent avec de vrais processus, pas avec un FFmpeg.
- **Date :** 2026-11-25
- **Portée :** `server/streaming/` : `session.go` (`Freeze`, `throttleStep`), `manager.go`
  (`Supersede`), `cores.go` (nouveau), `cpu_cost.go` (nouveau), `pipeline_log.go` (nouveau),
  `workspace.go`, `encoder.go`, `ffmpeg.go`, `handler.go`, `docker-compose.yml`.
- **Précise** l'ADR-0033 (sessions remplacées et leur grâce de 30 s) : la grâce ne change pas, ce
  qui tourne pendant elle change.

## Contexte

Les réglages du transcodage ont été pensés pour un Xeon double socket sans GPU. Sur une petite
machine, deux défauts faisaient saccader le lecteur, sans qu'aucun journal ne les nomme :

1. **Une session remplacée continuait d'encoder.** Un saut, un changement de qualité ou de
   sous-titre incrusté ouvrent une nouvelle session sur le même ticket, et l'ancienne vit encore
   30 s (ADR-0033), parce que le client montre encore son image pendant l'ouverture de la nouvelle.
   Pendant ces 30 s, deux FFmpeg se disputaient la machine, alors que seul le nouveau avait un
   lecteur. Sur une machine qui tient une session de justesse, c'est la nouvelle qui paie (raisonné,
   pas mesuré : le banc de la phase 0 servira à le chiffrer).
2. **Les cœurs étaient ceux de l'hôte, pas ceux du conteneur.** `maxEncoderThreads` valait 16 et le
   plafond de sessions `NumCPU()/2`. Or `NumCPU` ignore le quota d'un `docker --cpus`, que
   `GOMAXPROCS` suit depuis Go 1.25 (`go.mod` est en 1.27). Un conteneur à 4 cœurs sur un hôte de
   32 lançait 16 threads par session et en permettait seize.

## Décision

**Gel.** `SessionManager.Supersede` appelle `TranscodeSession.Freeze` sur chaque session qu'il
remplace : SIGSTOP tout de suite, et un état `frozen` que le bridage (`throttleStep`) respecte et ne
relance jamais. La session reste dans le gestionnaire et son dossier reste servi : les segments déjà
écrits sont lisibles jusqu'à sa destruction, au bout de la grâce. `Kill` envoie toujours SIGCONT avant
SIGTERM.

Le bridage et le gel signalent sous le même verrou (`s.mu`). Sans cela, un bridage qui a lu « pas
gelé » puis relance après la pose du gel annulerait SIGSTOP.

Une session en attente (`standby`) n'est jamais gelée : elle n'est remplacée qu'après `Claim`, et si
un départ ordinaire l'emporte avant, `Claim` ne la dégèlerait pas dans la grâce. Le gel est donc
sauté pour elle.

**Cœurs.** Un seul helper, `availableCores` (`GOMAXPROCS(0)`, remplaçable dans les tests), dont
viennent `encoderThreads()` (`min(16, cœurs)`, au moins 1) et le défaut de `maxTranscodes()`
(`max(cœurs/2, 4)`).

**Mesure.** À la fin d'une session, le journal donne le temps CPU de FFmpeg rapporté aux secondes de
film produites (cœurs par seconde de film), et `TranscodeSession.CPUCost()` le rend aux phases
suivantes. Le journal de démarrage nomme le pipeline (décodage, tone mapping, encodeur, preset,
threads) ; `decodeMode` écrit à la fois la commande et la ligne, pour qu'elles ne divergent pas.

## Conséquences

- Une session remplacée ne coûte plus de CPU pendant sa grâce. Contrepartie : un client qui demande
  encore, après le changement, un segment que la session gelée n'avait pas écrit attend jusqu'à
  la destruction. Le lecteur est censé avoir changé de source au premier segment de la nouvelle
  (`Claim`) ; ce n'est pas vérifié client par client.
- Le temps CPU n'est connu qu'à la sortie de FFmpeg. La rétroaction en continu (phase 5) devra
  lire `/proc/<pid>/stat` ; ce lot ne le fait pas.
- Le plafond par défaut baisse sur un conteneur bridé : c'est voulu, mais un opérateur qui avait posé
  `--cpus` sans `MAX_TRANSCODES` verra des refus 503 plus tôt. `MAX_TRANSCODES` reste le forçage.
