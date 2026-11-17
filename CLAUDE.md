# Directives Globales du Projet Onyx

Tu es l'assistant de développement sur **Onyx**. Tu dois appliquer **strictement** ces règles à chaque interaction.

## 1. Architecture Git & Workflow des Branches

Le dépôt utilise 4 branches strictes :
- **`master`** : Branche principale de production. Aucun push direct ou automatique n'est autorisé.
- **`beta`** : Branche d'intégration et de pré-production globale.
- **`tsuky`** : Branche de développement personnelle de Tsuky.
- **`fytroz`** : Branche de développement personnelle de Fytroz.

### Règles de synchronisation & Merge
- **Sur branche perso (`tsuky` ou `fytroz`) :** Push autorisé uniquement sur la branche perso active après commit (sauf instruction contraire).
- **Mise en `beta` :**
  1. Merger obligatoirement les deux branches (`tsuky` et `fytroz`) dans `beta` (`git checkout beta && git merge tsuky && git merge fytroz`).
  2. Une fois `beta` à jour, re-synchroniser (`merge` ou `rebase`) `tsuky` et `fytroz` avec `beta` pour les remettre d'équerre.
- **Mise en `master` (Protection Maximale) :**
  1. **JAMAIS** de push ou de merge automatique vers `master`.
  2. Uniquement sur demande explicite de l'utilisateur, **demande une double confirmation** avant d'exécuter l'opération.
  3. Après confirmation : exécute `git checkout master && git merge beta`, puis demande explicitement s'il faut lancer une **Release Prod**.

## 2. Gestion des Releases & Périmètres

**Règle absolue par défaut :** Ne lance **JAMAIS** de build ou de release automatiquement.

### Les 3 Niveaux de Versioning (Format X.Y.Z)
1. **Niveau 1 - Version Majeure (`X.0.0`) :** Uniquement pour un changement structurel profond de l'application (réinitialise Y et Z à 0).
2. **Niveau 2 - Version de Prod (`x.Y.0`) :** Chiffre `Y` incrémental à chaque mise en production validée depuis `master` (réinitialise Z à 0).
3. **Niveau 3 - Version de Test (`x.y.Z`) :** Chiffre `Z` incrémental à la volée depuis `tsuky`, `fytroz` ou `beta` (ex: `1.2.1`, `1.2.2`).

### Périmètres par Utilisateur
Identifie l'utilisateur actif via la branche Git courante (ou `CLAUDE.local.md`) :

- **Si utilisateur = `tsuky` (branche `tsuky`) :**
  - Il choisit manuellement les releases à envoyer (généralement niveau 3 sur sa branche, ou globales depuis `beta`).
  - **Périmètre autorisé :** Android, Android TV, webOS, Serveur, Client Windows.
  - **Interdiction stricte :** Ne **JAMAIS** lancer ou proposer de release sur l'environnement Apple (iOS / tvOS).

- **Si utilisateur = `fytroz` (branche `fytroz`) :**
  - Après chaque push sur sa branche, **demande-lui systématiquement** s'il souhaite lancer une release ou non.
  - **Périmètre proposé par défaut :** Uniquement l'environnement Apple (**iOS** iPhone/iPad et **tvOS**).
  - **Périmètre restreint (Serveur / Windows) :** Ne les propose **JAMAIS** par défaut. Ne les build/release que s'il te le demande et te force explicitement.

## 3. Obligations Techniques & Documentation

- **Internationalisation (i18n) Obligatoire :** À chaque ajout ou modification touchant l'interface utilisateur (UI), tu dois **impérativement** ajouter/mettre à jour les traductions en **Français (FR)** et en **Anglais (EN)**. Une tâche UI n'est jamais terminée sans les deux langues.
- **Architecture Decision Records (ADR) :** À chaque décision technique structurante (choix d'architecture, ajout de dépendance majeure, modification de schéma/API), crée ou mets à jour automatiquement un fichier ADR numéroté dans `docs/adr/` (voir `docs/agents/domain.md`).
- **Maintien continu de Graphify :**
  - Avant toute question d'architecture ou recherche dans le code, interroge `graphify-out/` via `graphify query "<question>"` (ou `path`/`explain`).
  - Après **chaque** modification de code, exécute systématiquement `graphify update .` en autonomie pour garder le graphe à jour. Ne signale jamais les diffs de `graphify-out/graph.json` comme du bruit.

## 4. Standards & Économie de Tokens

- **Exploration :** Utilise le skill `smart-explore` (AST) au lieu de lire les fichiers entiers. Lis toujours un fichier avant de le modifier, et ignore les fichiers de plus de 100 KB sauf nécessité absolue.
- **Exclusions strictes :** Ne lis jamais `app/build/`, `app/macos/build_xcode/`, `app/windows/flutter/ephemeral/`, `.claude/worktrees/`, `server/downloads/`, `server/data/`.
- **Skills & Docs :** Charge le skill `onyx-engineering` (`.claude/skills/onyx-engineering/`) pour le code. Issues dans GitHub (`docs/agents/issue-tracker.md`), contexte dans `CONTEXT.md`.
- **Anti-Hallucination :** Ne devine jamais les APIs, flags ou versions. Vérifie dans le code local avant d'agir.
