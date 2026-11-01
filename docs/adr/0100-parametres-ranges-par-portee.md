# ADR-0100 — Les paramètres rangés selon à qui ils s'appliquent

- **Statut :** accepté
- **Date :** 2026-11-01
- **Portée :** l'app (`app/lib/screens/settings/settings_categories.dart`,
  `app/lib/screens/settings/settings_sections.dart`, les pages `device_page.dart`,
  `account_page.dart`, `downloads_page.dart`, `playback_page.dart`, `logs_page.dart`,
  `users_page.dart`, `integrations_page.dart`, et les nouveaux `security_page.dart`,
  `server_logs_page.dart`, `widgets/other_devices_group.dart`, `widgets/image_cache_group.dart`,
  `widgets/settings_scope.dart`).

## Contexte

L'ADR-0071 a ramené la navigation à neuf entrées, mais il a regroupé les pages par voisinage de
thème, pas par la question qu'on se pose en cherchant un réglage : « ça concerne qui ? ». Résultat :

- « Général » mélangeait l'affichage, la langue, les notifications, les appareils à connecter, le
  cache des images, l'aide et le journal ;
- les appareils étaient à trois endroits (Général, Mon compte, Utilisateurs) et le stockage à
  deux (Général, Téléchargements) ;
- des réglages du serveur se cachaient dans des pages personnelles : les interrupteurs des
  journaux de lecture dans le journal de l'app, la politique de validation en deux étapes et le
  message à tous dans « Utilisateurs », le service de demandes (MediaHub) dans « Métadonnées » ;
- « Serveurs et partage » réunissait vos serveurs, la synchro Emby et les liens de partage, sans
  lien entre eux, pendant que « Serveurs liés » était une entrée à part ;
- la page Lecture mêlait des préférences de compte et des réglages d'appareil sans le dire.

## Décision

**Chaque réglage se range selon son périmètre : le compte, cet appareil, ou le serveur.** Le
compte et l'appareil sont dans « Mon espace », le serveur dans « Administration » ; le nombre
d'entrées de l'ADR-0071 (neuf au plus, cinq pour un membre) ne change pas.

| Entrée | Périmètre | Contenu |
|---|---|---|
| Mon compte (onglets) | compte | Profil (sécurité, code à deux étapes, appareils connectés, ajouter un appareil), Synchro Emby, Liens de partage |
| Lecture | compte puis appareil | préférences de compte, puis un intertitre « Propre à cet appareil » (ADR-0043) |
| Cet appareil | appareil | affichage, langue, notifications, aide, à propos |
| Téléchargements et stockage | appareil | téléchargements, réseau, cache des images |
| Serveurs | appareil | serveur actif, adresse, mes serveurs |
| Activité, Utilisateurs, Bibliothèque | serveur | inchangés, sauf ce qui n'était pas à eux |
| **Serveur** (onglets) | serveur | Services (TMDB, Fanart, MediaHub), Sécurité, Journaux, Message à tous, Serveurs liés |

Les adresses de `SettingsSections` sont conservées ; `security`, `server-logs` et `server` s'y
ajoutent. Une page qui mêle deux périmètres le dit avec `SettingsScopeHeading` ; une page d'un seul
périmètre le dit dans sa description.

### Ce qui change de place

- « Autres appareils » (connecter, installer) passe de Général à Mon compte, sous les appareils
  connectés (`OtherDevicesGroup`).
- Le cache des images passe de Général à Téléchargements et stockage (`ImageCacheGroup`). La
  catégorie reste visible sur Apple TV, où elle ne montre que ce cache.
- Les interrupteurs des journaux de lecture quittent le journal de l'app pour Serveur › Journaux.
  Le journal de l'app (`LogsPage`) ne montre plus que ce qui concerne l'appareil.
- La politique de validation en deux étapes et le message à tous quittent Utilisateurs pour
  Serveur ; la synchro Emby et les liens de partage rejoignent Mon compte ; Serveurs liés devient un
  onglet de Serveur.
- « Métadonnées » devient « Services » : la page porte aussi MediaHub, qui n'a rien de métadonnées.
- « Général » redevient « Cet appareil », puisque le nom dit le périmètre.

## Conséquences

- **Contredit l'ADR-0071 §1, §2 et §5.** La liste des entrées change, « Utilisateurs » n'a plus
  d'onglet « Message à tous », et le groupe « Autres appareils » n'est plus une ligne de « Général ».
  Le §3 (les pages n'en savent rien), le §4 (une page garde son adresse) et la règle des neuf
  entrées tiennent toujours. **Contredit aussi le §6** : le cache des images est de retour dans une
  page de stockage, mais c'est « Téléchargements et stockage », seul endroit où l'on gère la place.
- **Revient sur un choix de `logs_page.dart`** : les interrupteurs serveur étaient avec le journal
  « parce que ce qui décide si les journaux existent appartient à la page où on les lit ». Un
  administrateur qui cherche un réglage du serveur le cherche d'abord dans « Serveur » ; la page
  Journaux renvoie à l'Historique, où l'on lit les journaux.
- Les notifications restent dans « Cet appareil » : l'autorisation est celle du système de
  l'appareil (ADR-0059), « Nouvelles demandes » comprise.
- Un nouveau réglage se range en répondant d'abord à « ça concerne qui ? ». Le test
  `settings_screen_test.dart` épingle que les réglages du serveur ne se trouvent que dans l'entrée
  Serveur, qu'un membre ne la voit pas, et que Mon compte porte Emby et le partage.
- La recherche des paramètres (`settings_search.dart`) liste ses réglages à la main : ses entrées
  « Connecter un appareil », « Installer Onyx… » et « Cache des images » pointent encore vers
  `device`, et celles des journaux serveur, de la sécurité et du message à tous vers leurs anciennes
  entrées. Les adresses restent valides mais ouvrent la mauvaise page tant qu'elles ne sont pas
  corrigées.
