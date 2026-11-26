# Boutons primaires blancs partout et confirmation avant déconnexion

- **Statut :** accepté
- **Date :** 2026-11-25
- **Portée :** `theme/app_theme.dart` (`filledButtonTheme`), `widgets/global/detail_hero.dart` (`HeroPillStyle.primary`, `HeroPillStyle.request`), `widgets/global/detail_actions.dart`, `screens/requests/widgets/request_detail_actions.dart`, `widgets/global/onyx_dialog.dart` (`confirmSignOut`), `widgets/global/account_menu.dart`, `screens/settings/pages/account_page.dart`, `l10n/en.dart`.
- **Prolonge** `PROJECT_DESIGN.md` §8, l'[ADR-0112](0112-sur-televiseur-la-commande-focalisee-se-remplit-de-blanc.md) et l'[ADR-0128](0128-les-dialogues-du-bureau-et-du-telephone-partagent-un-seul-cadre-onyx.md).

## Contexte

Lors de la revue visuelle sur l'application Web (`https://onyx.tsuky.ovh/`), trois écarts UI/UX ont été constatés et validés :

1. `AppTheme.dark.filledButtonTheme` ne déclarait ni `backgroundColor` ni `foregroundColor`, faisant hériter tous les `FilledButton` (`Paramètres > Serveur`, dialogues, assistant, etc.) de `ColorScheme.primary` (`#0A84FF` bleu). De même, `HeroPillStyle.request` utilisait un fond et un halo bleus (`AppColors.request`). Cela contredisait `PROJECT_DESIGN.md` (§8 : boutons primaires blancs, accent bleu réservé au focus, à la progression et aux liens).
2. Sur les fiches Film, Série (`DetailActions`) et Demande disponible (`RequestDetailActions.play`), le bouton principal de lecture utilisait `HeroPillStyle.glass` (gris translucide), le mettant visuellement sur le même plan que les actions secondaires (`Ma liste`, `Plus`) et en rupture avec le bouton blanc du Hero d'accueil.
3. Dans le menu du compte et dans *Paramètres > Mon compte*, `Se déconnecter` appelait `auth.logout()` sans confirmation, alors que l'entrée voisine avec `Paramètres` dans le menu compact.

## Décision

1. **`filledButtonTheme` passe en primaire blanc** (`AppColors.textPrimary` / `AppColors.background`, désactivé `surfaceHover` / `textMuted`) avec `focusRinged(..., restOnTv: FocusFill.glass)` pour conserver la règle TV de l'ADR-0112.
2. **`HeroPillStyle.primary` et `HeroPillStyle.request` sont blancs au repos hors TV** (`AppColors.textPrimary` / `AppColors.background`, sans halo bleu sur `request`) et passent en `FocusFill.glass` au repos sur TV. `DetailActions` et `RequestDetailActions.play` utilisent `HeroPillStyle.primary`.
3. **`confirmSignOut(context)`** centralise une confirmation `showOnyxConfirm(..., destructive: true)` avant `auth.logout()` pour `AccountMenu` et `AccountPage`.

## Conséquences

- Les boutons d'action `FilledButton` (y compris `FilledButton.tonalIcon`), les boutons « Demander » sur saisons et les boutons « Lecture / Reprendre / Lire » sur fiches adoptent uniformément le traitement primaire blanc *Quiet Premium*, tout en restant en verre au repos sur téléviseur (ADR-0112).
- La déconnexion depuis le menu du compte ou les réglages exige une confirmation explicite (le focus par défaut reste sur « Annuler »).
- Épinglé par `focus_fill_test.dart`, `account_menu_test.dart`, `detail_actions_test.dart`, `request_detail_hero_test.dart` et `l10n_coverage_test.dart`.
