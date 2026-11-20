# ADR-0165 — Un assistant guidé pour le premier lancement du serveur

- **Statut :** accepté, à la demande de l'utilisateur (2026-11-20 : refaire le premier lancement
  en assistant guidé, avec un explorateur de dossiers, une clé TMDB testable et un service de
  demandes testable). Côté app seulement, codé contre un contrat serveur écrit en parallèle ;
  vérifié en test avec de faux clients, **pas encore lancé contre le vrai serveur ni sur un
  appareil**.
- **Date :** 2026-11-20
- **Portée :** `app/lib/models/first_run_setup.dart` (nouveau : `FsListing`, `FsFolder`, `FsCrumb`,
  `TmdbTest`, `SetupState`), `app/lib/services/api/setup.dart` (nouveau : `browseFolders`,
  `testTmdbKey`, `getSetupGuide`, `completeSetup`), `app/lib/providers/setup_provider.dart`
  (nouveau), `app/lib/screens/settings/widgets/folder_picker.dart` (nouveau),
  `library_editor_dialog.dart`, `libraries_group.dart`, `integration_fields.dart`,
  `tmdb_settings_form.dart`, `request_service_form.dart` (extraits de la page Services),
  `app/lib/screens/settings/pages/integrations_page.dart`, `app/lib/screens/setup/` (nouveau :
  l'assistant, ses quatre étapes, la checklist), `app/lib/screens/home/home_screen.dart` et
  `home_empty_view.dart`, `app/lib/screens/auth/widgets/setup_code_hint.dart`, `app/lib/main.dart`.
- **Complète** l'ADR-0155 (bibliothèques préremplies) : l'explorateur remplace les pastilles de
  dossiers libres, qui restent le repli d'un serveur sans explorateur. **Ne contredit** aucune
  ADR.

## Contexte

Un serveur neuf demandait à son propriétaire de tout deviner : créer un compte, puis trouver dans
les Paramètres où déclarer une bibliothèque en tapant à la main un chemin que seul le compose
connaît, puis, sans que rien ne le dise, qu'une clé TMDB fait venir les affiches. Une clé fausse ne
se voyait qu'à l'absence d'affiches. Le service de demandes, lui, ne peut pas marcher sans TMDB :
le serveur le refuse (409), mais l'écran n'en disait rien.

## Décision

1. **Un seul explorateur de dossiers** (`FolderPicker`) : fil d'Ariane cliquable, sous-dossiers
   avec le type deviné et le nombre de vidéos (« 50+ » quand le serveur a cessé de compter), les
   dossiers déjà pris grisés et hors du parcours, « Choisir ce dossier » pour le dossier ouvert.
   Une racine vide (`empty_root`) affiche un diagnostic avec la ligne à ajouter au compose. Le
   widget ne connaît pas `ApiClient` : l'appelant lui passe un chargeur (`FolderLoader`), ce qui le
   rend testable. L'éditeur de bibliothèque l'emploie à la place du chemin tapé ; la saisie à la
   main reste sous « Avancé ». Nom et type se préremplissent d'après le dossier choisi, et un nom
   tapé à la main n'est jamais remplacé (comme l'ADR-0155).
2. **L'assistant** (`SetupWizardScreen`) : quatre étapes (bibliothèques, TMDB, demandes, fin), une
   barre de progression, Précédent. Il s'ouvre une seule fois par appareil et par serveur, après la
   création du compte propriétaire, quand `GET /api/setup/state` dit `completed: false` et que le
   compte a `manage_settings` (`shouldOpenSetupWizard`). Chaque étape agit tout de suite sur le
   serveur : la bibliothèque créée est analysée pendant qu'on règle TMDB, et quitter ne perd rien.
3. **Une étape passée devient une ligne de la checklist de l'accueil** (« Finir l'installation :
   2/3 »), qui rouvre l'étape. Elle remplace le simple « Aucune bibliothèque » de l'accueil vide.
   « Ignorer » et « Terminer » appellent `POST /api/setup/complete` : le serveur retient la clôture
   pour tous les appareils. Le serveur reste la source ; l'app ne retient que « cet appareil a déjà
   ouvert l'assistant » (`setup_wizard_offered:<serveur>`), pour ne pas le rouvrir à chaque
   lancement après qu'on l'a quitté.
4. **Une clé TMDB testable.** `TmdbSettingsForm` (page Services et étape 2) a un bouton **Tester**
   qui rend vert ou rouge avec la cause : clé refusée (`invalid_key`, « copiez la clé API v3, pas le
   jeton d'accès ») n'est pas TMDB injoignable depuis le serveur (`unreachable`, « la clé n'est pas
   en cause »). L'étape dit à quoi sert la clé, comment l'obtenir, qu'elle est gratuite pour un usage
   non commercial (un usage commercial demande une licence TMDB), et ouvre
   `themoviedb.org/settings/api` avec `openExternalUrl`, déjà employé par le dépôt (`url_launcher`
   n'est pas une dépendance : on n'en ajoute pas). Sans navigateur (téléphone), l'adresse est copiée
   et dite ; sur téléviseur, elle est écrite en clair à la place du bouton. La langue des titres est
   préremplie d'après la langue de l'app. L'étape se passe, avec l'avertissement « sans clé, pas
   d'affiches ni de métadonnées ». L'attribution TMDB figure déjà dans À propos
   (`AboutGroup.tmdbAttribution`).
5. **Le service de demandes est grisé tant que TMDB manque.** `RequestServiceForm` (page Services et
   étape 3) est le code de la page Services, sorti dans son propre fichier plutôt que dupliqué. Son
   verrou suit `requests.available` de l'état d'installation ; dans l'assistant, le bouton
   « Configurer TMDB » ramène à l'étape 2. Dans les Paramètres le groupe TMDB est juste au-dessus,
   et le verrou n'a pas de bouton : un défilement à la main passerait à côté de dpad
   (`no_parallel_focus_system_test`). Un état inconnu ne verrouille rien : le serveur refusera,
   avec sa raison.
6. **Un serveur plus ancien répond 404 : l'app se comporte comme avant.** Chaque nouvelle méthode
   rend `null` au lieu de lever (`browseFolders` à la racine, `testTmdbKey`, `getSetupGuide`),
   `completeSetup` ignore le 404. Sans état d'installation, `SetupProvider.needsSetup` est faux :
   ni assistant, ni checklist, et l'éditeur de bibliothèque garde son chemin tapé et ses pastilles.
7. **Sur téléviseur**, la saisie d'une clé est pénible : l'étape le dit, son bouton principal (qui
   a le focus) est « Passer », et la checklist la reprend depuis un autre appareil. Toutes les
   lignes et boutons sont des cibles du parcours habituel, comme les Paramètres.
8. **À l'inscription du propriétaire**, quand le serveur demande un code d'installation
   (`setup_code_required`), l'écran affiche `docker logs onyx-server` sous le champ.

## Conséquences

- Contrat côté serveur, écrit par une autre session : `GET /api/fs/browse`,
  `POST /api/settings/tmdb/test`, `GET /api/setup/state`, `POST /api/setup/complete`. Les modèles
  Dart sont tolérants (champ absent = valeur neutre, cause inconnue = `unknown` avec la phrase du
  serveur). Les fichiers de `contract/` pour ces réponses restent à ajouter côté serveur ; les
  tests Dart épinglent les formes en ligne en attendant.
- La page Services passe de 527 à ~230 lignes ; ses formulaires sont partagés avec l'assistant, et
  un réglage de plus s'y ajoute en un seul endroit.
- Le dossier `screens/setup/` est nouveau ; `screens/settings/widgets/` porte l'explorateur et les
  formulaires de service, car il emploie les `Icons` Material que `app_icons_guard_test` interdit
  dans `widgets/global` et `screens/home`.
- Le compte « propriétaire » est reconnu par `manage_settings`, pas par un état propre à
  l'installation : un second administrateur voit aussi la checklist tant que l'installation n'est
  pas close. C'est voulu (n'importe quel administrateur peut la finir).

## À vérifier sur l'appareil

- Contre le vrai serveur : l'explorateur sur un vrai montage (dossiers couverts, compte de vidéos
  plafonné, racine vide), le test TMDB avec une vraie clé, une fausse, et le serveur sans accès à
  Internet, le verrou des demandes puis son déverrouillage après l'enregistrement de TMDB.
- Sur téléviseur (Android TV, webOS, tvOS) : le D-pad dans l'explorateur et dans la checklist, le
  focus qui reste visible, l'adresse TMDB lisible depuis le canapé.
- Sur téléphone : le bouton « Ouvrir themoviedb.org/settings/api » n'ouvre rien (pas de lanceur de
  liens) et copie l'adresse ; à confirmer que c'est acceptable, sinon il faudra `url_launcher`.
