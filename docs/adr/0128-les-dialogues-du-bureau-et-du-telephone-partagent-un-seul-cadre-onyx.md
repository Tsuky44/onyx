# ADR-0128 — Les dialogues du bureau et du téléphone partagent un seul cadre Onyx

- **Statut :** accepté. Vérifié par `test/onyx_dialog_test.dart` ; pas encore vu à l'écran dans l'app lancée.
- **Date :** 2026-11-14
- **Portée :** `widgets/global/onyx_dialog.dart` (`OnyxDialog`, `OnyxDialogAction`, `showOnyxDialog`,
  `showOnyxConfirm`) et les dialogues convertis : `device_library_screen`, `show_episode_actions`,
  `show_metadata_actions`, `request_moderation_dialogs`, `library_editor_dialog`, `settings_ui`
  (`confirmSettingsAction`), `shared_link_guest`, `app_update_dialog`, `bulk_download_delete`,
  `detail_synopsis`, `join_watch_party_dialog`, `media_download_button`, `metered_download_dialog`,
  `otp_code_dialog`, `season_download_button`, `share_media_dialog`.
- **Prolonge** l'[ADR-0126](0126-le-menu-du-compte-met-les-profils-en-tete.md) (le menu du compte, dont le
  verre et le filet servent de référence).

## Contexte

L'app comptait 24 `AlertDialog` Material, chacun réglé à sa façon (fond `surface` ou `surfaceElevated`,
rayon 16 par défaut, boutons de texte). Une suppression s'écrivait d'un bouton de texte rouge, ou pas
rouge du tout : le bouton « Supprimer » d'un dialogue ressemblait à « Plus tard » d'un autre.

## Décision

Une seule fenêtre, `OnyxDialog` : fond `surfaceElevated`, rayon 20, filet `glassBorder`, ombre ample,
largeur 420 px (réglable), padding 24. Un disque de 44 px porte l'icône (rouge pâle pour une suppression),
puis le titre (20 px, 700), le message (`textSecondary`, 14 px, interligne 1,5), et des capsules de 44 px :
verre pour l'issue secondaire, blanche pour l'action principale, rouge pleine si `destructive`.

- `showOnyxConfirm` couvre les questions à deux issues et rend vrai/faux. Une confirmation de
  suppression est `destructive`, et son focus clavier démarre sur « Annuler » : Entrée ne supprime pas.
- Les dialogues à contenu (champ, liste, progression) passent le leur à `OnyxDialog.content` et gardent
  leur logique ; seuls le cadre et les boutons changent.
- Deux capsules s'alignent à largeur égale ; trois ou plus s'empilent (le choix du réseau limité, dont les
  libellés ne tiennent pas à trois sur une ligne).
- `showOnyxDialog` pose l'apparition : `AppMotion.standard`, `AppMotion.curve`.

**Sur TV, `OnyxDialog` rend l'`AlertDialog` du thème** (boutons Material, focus télécommande inchangé) :
la TV est refaite à part. Les dialogues de `lib/tv/`, du lecteur, des téléchargements, de l'administration
et des serveurs ne sont pas convertis ici.

## Conséquences

- Un dialogue nouveau n'écrit plus d'`AlertDialog` : il prend `showOnyxConfirm` ou `OnyxDialog`.
- Les tests qui cherchaient `AlertDialog` dans les fichiers convertis cherchent `OnyxDialog`.
- Les dialogues restants (`downloads_screen`, `user_admin_sections`, `servers_screen`,
  `linked_servers_section`, `access_requests_section`, `list_detail_screen`, `watch_list_editor_dialog`,
  `player_shortcuts`) se convertissent dans leurs propres chantiers.
