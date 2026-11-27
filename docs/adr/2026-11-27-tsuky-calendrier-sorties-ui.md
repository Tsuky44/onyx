# Calendrier des sorties : maquette UI et seam en mémoire

- **Statut :** accepté, complété par `2026-11-27-tsuky-calendrier-sorties-serveur.md` (données du serveur à la place du jeu factice)
- **Date :** 2026-11-27
- **Portée :**
  - Maquette : `design-plans/onyx-calendrier-maquette.html`.
  - App : `models/calendar.dart`, `providers/calendar_provider.dart`, `screens/calendar/`, `screens/home/home_calendar_row.dart`, `screens/shell/` (`ShellTabs`, `MainShell`, `ShellDesktopHeader`, `ShellTvHeader`, `MobileBottomNav`), `screens/library/show_detail_screen.dart`, `screens/library/show_hero_actions.dart`, `widgets/global/media_countdown.dart`, `widgets/global/follow_show_button.dart`, `theme/app_icons.dart`, `l10n/en.dart`.

## Contexte

1. L'app doit accueillir un calendrier personnel des sorties (« À venir ») limité aux séries suivies ou en cours, aux titres demandés et aux films/séries présents sur le serveur.
2. Le backend Go, les endpoints API et la persistance serveur du suivi seront conçus et branchés dans un second temps.
3. L'objectif de cette première étape est de livrer fidèlement toute l'interface de la maquette (`design-plans/onyx-calendrier-maquette.html`) et le branchement des boutons et de la navigation, avec des données factices en mémoire.

## Décision

1. **Points d'entrée par appareil :**
   - **Bureau et TV :** onglet « À venir » (`ShellTabs.calendar`) placé dans la barre entre « Demandes » et « Listes ».
   - **Téléphone :** entrée « À venir » rangée dans le menu « Plus » (`MobileBottomNav._overflow`), sans alourdir la capsule flottante du bas.
   - **Accueil :** rangée « Cette semaine » juste sous « Reprendre la lecture » (masquée s'il n'y a rien dans les 7 jours), avec « Tout voir › » ouvrant l'onglet « À venir ».
   - **Fiche série :** pilule « + Suivre / ✓ Suivie » (`FollowShowButton`, variante 1) dans `ShowHeroActions`, accompagnée sous le compte à rebours (`MediaCountdown`) d'un lien cliquable « Voir dans le calendrier › » et de la raison du suivi automatique (variante 3).
2. **Vues adaptatives de la page « À venir » :**
   - **Téléphone (`< 700 px`) :** vue **A · Agenda** (en-têtes de jours collants, filtre `Tout` / `Séries` + puces source, vignette 16:9 avec lecture directe si disponible, bouton « Gérer les séries suivies » ouvrant une feuille dédiée).
   - **Bureau et tablette (`>= 700 px`, hors TV) :** vue **B · Semaine** par défaut avec bascule **Semaine / Mois** vers **C · Mois** (grille mensuelle + panneau latéral de détail du jour sélectionné).
   - **Téléviseur (`TvScope`) :** vue **D · Affiche** (bannière hero de la prochaine sortie avec compte à rebours géant + rangées horizontales navigables au D-pad via `TvFocusable` et `TvRegion`).
3. **Seam unique en mémoire (`CalendarProvider`) :**
   - Toute la donnée fictive et l'état suivi/retiré vivent dans `CalendarProvider` sans aucun appel réseau.
   - Le futur branchement serveur n'aura qu'à remplacer les sources internes de `CalendarProvider` (ex. chargement depuis `ApiClient` + persistance du suivi) sans toucher aux écrans ni aux widgets.

## Conséquences

- Zéro route serveur ni appel réseau ajouté pour le moment.
- Toutes les vues et interactions (filtres, navigation semaine/mois, sélection de jour, bascule Suivre/Suivie, gestion des séries suivies, navigation depuis l'accueil et la fiche série) sont immédiatement testables et alignées sur Quiet Premium (`AppColors`, `AppType`, `AppMotion`, `AppIcons`, `tr()`/`en.dart`).
