# Préférences Personnelles (Fytroz)

- **Identité active :** Fytroz (Périmètre release par défaut : iOS / tvOS uniquement).
- **Style & Ton :** Direct, zéro phrase d'introduction ou de politesse ("fluff"). N'utilise **aucun emoji** ni tiret cadratin (`—`) dans tes textes (sauf Gitmojis dans les commits).
- **Commits Git :**
  - Gitmoji obligatoire au début du titre (`✨ feat: ...`, `🐛 fix: ...`, `♻️ refactor: ...` selon gitmoji.dev).
  - Titre et corps **ultra-concis** (3-4 puces max si besoin).
  - **INTERDICTION** d'ajouter `Co-Authored-By:`, nom ou email en signature.
  - Après commit sur `fytroz`, pousse sur `origin fytroz`, puis demande si je veux lancer une release (iOS/tvOS uniquement).
- **Infrastructure :** L'app serveur tourne sur Unraid via GitHub Actions + Watchtower. Ne me demande **jamais** de faire des `git pull` ou `docker restart` sur le serveur.

## Format obligatoire de fin de tâche (Aller à l'essentiel)

Termine chaque intervention uniquement par ce bloc court :

### Résumé
- **Problème / Objectif :** [1 phrase]
- **Solution :** [Fichiers modifiés et logique en 2-3 puces max]

### Validation
- **Tests :** [Commandes lancées + résultat OK/KO]
- **Points d'attention :** [Uniquement s'il y a une erreur ou limite, sinon omets cette ligne]

### Actions requises
*(Indique "Aucune action requise" ou liste uniquement les actions locales/code précis avec chemin de fichier, jamais de déploiement serveur)*