import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/en.dart';

/// Garde-fou d'ADR-0047 : un texte français affiché sans passer par `tr()`
/// resterait en français dans une interface anglaise, et rien ne casserait.
/// Ce test parcourt les écrans, widgets et vues TV, et refuse tout littéral
/// qui ressemble à du français sans être une clé de [kEnglish].
///
/// Si un texte est vraiment affiché : passe-le par `tr()` et ajoute-le à
/// `lib/l10n/en.dart`. N'ajoute à la liste blanche que ce qui n'est jamais lu
/// par l'utilisateur, avec la raison.
const _roots = ['lib/screens', 'lib/widgets', 'lib/tv'];

/// Fichiers dont les littéraux sont des journaux ou des traces, jamais de
/// l'interface.
final _logFiles = RegExp(r'(_trace|startup_timeline|/mpv_)');

/// Fichiers dont tous les littéraux français sont du diagnostic, avec la
/// raison. Un littéral de ces fichiers qui s'afficherait un jour doit sortir
/// de cette liste.
const _diagnosticFiles = <String, String>{
  'screens/player/playback/seek_timeline.dart':
      'describe() est une ligne de journal du lecteur (debugPrint)',
  'screens/player/hooks/use_auto_quality.dart':
      'les raisons de bascule (`why`) vont dans les journaux de la qualité auto',
  'tv/input/tv_arrow_gate.dart': "raisons d'un journal de focus",
  'tv/tv_touchpad.dart': "raisons d'arrêt d'inertie, lues en debug seulement",
};

/// Le début d'une instruction qui n'affiche rien à l'utilisateur : journaux,
/// assertions, erreurs internes que l'interface n'affiche pas telles quelles.
final _internalStatement = RegExp(
    r'(debugPrint|ClientLog\.|_startup\.note\(|developer\.log|\blog\(|\bprint\(|'
    r'[Tt]race\w*\(|assert\(|'
    r'throw |Exception\(|StateError\(|ArgumentError|UnimplementedError|'
    r'UnsupportedError|FlutterError\()');

/// Littéraux français qui ne sont pas du texte affiché, et pourquoi. Chaque
/// entrée est le littéral exact.
const _allowed = <String, String>{
  r'$label+léger':
      'étiquette de profil de lecture, écrite dans les journaux seulement',
  'logs erreur debug diagnostic':
      'mots-clés de recherche des réglages, jamais affichés',
  'offline stockage espace supprimer':
      'mots-clés de recherche des réglages, jamais affichés',
  'dossiers folders chemins ajouter supprimer':
      'mots-clés de recherche des réglages, jamais affichés',
  'invite code lien compte':
      'mots-clés de recherche des réglages, jamais affichés',
  'Lecture sur un autre appareil':
      'libellé de débogage d’un FocusNode (RemotePlaybackBanner), jamais affiché',
  r'- /chemin/vers/vos/films:$mount/Films:ro':
      'ligne d’exemple d’un volume Docker : un chemin type à remplacer, pas un texte',
};

final _accent = RegExp('[àâäçéèêëîïôöûùüÿœæÀÂÇÉÈÊËÎÏÔÛÙÜŒ]');

/// Mots que l'anglais n'emploie pas. Un seul suffit à classer un littéral
/// comme français, à condition qu'il en ait plusieurs mots ou qu'il soit
/// dans [_singleWords].
final _frenchWords = RegExp(
    r'\b(le|la|les|des|une|pour|avec|dans|sur|est|pas|vous|votre|vos|'
    r'aucun|aucune|ou|et|du|au|aux|ce|cette|ces|nous|mot|passe|erreur|'
    r'impossible|fichier|fichiers|serveur|compte|lecture|bibliothèque|'
    r'supprimer|annuler|valider|enregistrer|chargement|réessayer)\b',
    caseSensitive: false);

/// Les mots français isolés qui s'afficheraient seuls (« Annuler »).
const _singleWords = {
  'annuler',
  'valider',
  'enregistrer',
  'supprimer',
  'fermer',
  'retour',
  'erreur',
  'lecture',
  'suivant',
  'précédent',
  'oui',
  'non',
  'modifier',
  'ajouter',
  'réessayer',
  'continuer',
  'terminé',
  'chargement',
};

/// Un littéral ou une suite de littéraux collés par juxtaposition.
class _Literal {
  _Literal(this.value, this.start, this.line);
  final String value;
  final int start;
  final int line;
}

/// Extrait les littéraux de [src] en ignorant les commentaires. Le contenu
/// d'une interpolation `${…}` est sauté : il contient du code, pas du texte.
List<_Literal> _literals(String src) {
  final out = <_Literal>[];
  var i = 0;
  var line = 1;

  while (i < src.length) {
    final c = src[i];
    if (c == '\n') {
      line++;
      i++;
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      final end = src.indexOf('*/', i + 2);
      final stop = end < 0 ? src.length : end + 2;
      line += '\n'.allMatches(src.substring(i, stop)).length;
      i = stop;
      continue;
    }
    if (c == "'" || c == '"') {
      final raw = i > 0 && src[i - 1] == 'r';
      final triple = src.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      final startLine = line;
      final start = i;
      i += quote.length;
      final buffer = StringBuffer();
      while (i < src.length && !src.startsWith(quote, i)) {
        final ch = src[i];
        if (ch == '\n') line++;
        if (!raw && ch == r'\' && i + 1 < src.length) {
          final next = src[i + 1];
          buffer.write(switch (next) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            _ => next,
          });
          i += 2;
          continue;
        }
        if (!raw && ch == r'$' && i + 1 < src.length && src[i + 1] == '{') {
          var depth = 1;
          i += 2;
          while (i < src.length && depth > 0) {
            if (src[i] == '{') depth++;
            if (src[i] == '}') depth--;
            if (src[i] == '\n') line++;
            i++;
          }
          buffer.write(r'${}');
          continue;
        }
        buffer.write(ch);
        i++;
      }
      i += quote.length;
      out.add(_Literal(buffer.toString(), start, startLine));
      continue;
    }
    i++;
  }
  return _merge(src, out);
}

/// Fusionne les littéraux voisins : `'a' 'b'` est un seul texte.
List<_Literal> _merge(String src, List<_Literal> raw) {
  final out = <_Literal>[];
  _Literal? current;
  var currentEnd = 0;
  for (final lit in raw) {
    if (current != null &&
        src.substring(currentEnd, lit.start).trim().isEmpty) {
      current =
          _Literal(current.value + lit.value, current.start, current.line);
      out[out.length - 1] = current;
    } else {
      current = lit;
      out.add(lit);
    }
    // Fin du littéral : on cherche la fin de la quote qui a ouvert [lit].
    currentEnd = _endOf(src, lit.start);
  }
  return out;
}

int _endOf(String src, int start) {
  final c = src[start];
  final raw = start > 0 && src[start - 1] == 'r';
  final quote = src.startsWith(c * 3, start) ? c * 3 : c;
  var i = start + quote.length;
  while (i < src.length && !src.startsWith(quote, i)) {
    if (!raw && src[i] == r'\') {
      i += 2;
      continue;
    }
    if (!raw && src[i] == r'$' && i + 1 < src.length && src[i + 1] == '{') {
      var depth = 1;
      i += 2;
      while (i < src.length && depth > 0) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') depth--;
        i++;
      }
      continue;
    }
    i++;
  }
  return i + quote.length;
}

bool _looksFrench(String text) {
  if (_accent.hasMatch(text)) return true;
  final trimmed = text.trim().toLowerCase();
  if (_singleWords.contains(trimmed)) return true;
  if (!trimmed.contains(' ')) return false;
  return _frenchWords.hasMatch(text);
}

/// Le début de l'instruction qui contient la position [start], pour savoir si
/// c'est un journal.
String _statementBefore(String src, int start) {
  var from = start;
  var seen = 0;
  while (from > 0 && seen < 600) {
    final ch = src[from - 1];
    if (ch == ';') break;
    from--;
    seen++;
  }
  return src.substring(from, start);
}

void main() {
  test('aucun texte français n’échappe à tr() dans les écrans', () {
    final hidden = <String>[];
    for (final root in _roots) {
      for (final file in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final path = file.uri.path;
        if (_logFiles.hasMatch(path)) continue;
        if (_diagnosticFiles.keys.any(path.endsWith)) continue;
        final src = file.readAsStringSync();
        for (final lit in _literals(src)) {
          final text = lit.value;
          // Une lettre seule est une table de pliage d'accents (é → e).
          if (text.length == 1 || !_looksFrench(text)) continue;
          if (kEnglish.containsKey(text)) continue;
          if (_allowed.containsKey(text)) continue;
          if (_internalStatement.hasMatch(_statementBefore(src, lit.start))) {
            continue;
          }
          hidden.add('$path:${lit.line}: $text');
        }
      }
    }
    expect(hidden, isEmpty,
        reason: 'ces textes ressemblent à du français affiché sans tr() : '
            'passe-les par tr() et ajoute-les à lib/l10n/en.dart (ADR-0047)');
  });
}
