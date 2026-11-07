@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un seul système de focus : dpad, derrière `lib/tv/nav/` et `lib/tv/input/`
/// (ADR-0110, plan `docs/refonte-navigation-dpad.md`).
///
/// La navigation au D-pad s'était empilée en mécanismes qui se corrigeaient
/// les uns les autres : une politique de parcours, des entrées de zone, des
/// mémoires, des volets, des rangées, un défilement par pas, et une
/// cinquantaine de gestionnaires de touches isolés. Chaque nouvelle couche
/// réparait un effet de bord de la précédente — deux `requestFocus` et deux
/// défilements par flèche, un double Retour sur Android. Ce test empêche
/// qu'une couche de plus s'ajoute à côté de dpad pendant la migration.

/// Ce qui fait un second système de focus, et pourquoi.
const Map<String, (String pattern, String why)> _constructs = {
  'FocusTraversalGroup': (
    r'\bFocusTraversalGroup\(',
    'dpad pose sa politique de parcours ; une zone est un TvRegion',
  ),
  'TraversalPolicy': (
    r'\b\w*TraversalPolicy\b',
    'une politique de parcours à côté de celle de dpad',
  ),
  'DirectionalFocus': (
    r'\bDirectionalFocus(Intent|Action)\b',
    'les flèches passent par dpad, jamais par les intents du framework',
  ),
  'Shortcuts': (
    r'\b(Callback)?Shortcuts\(|\bshortcuts:',
    'un second jeu de raccourcis ; les touches sont dans OnyxDpad',
  ),
  'onKeyEvent': (
    r'\bonKey(Event)?:',
    'un gestionnaire de touches isolé ; une flèche passe par TvArrowGate',
  ),
  'KeyboardHandler': (
    r'HardwareKeyboard\.instance\.addHandler|add(Early|Late)KeyEventHandler',
    'un gestionnaire global vu avant tout le monde et que rien n’arrête',
  ),
  'ensureVisible': (
    r'\bScrollable\.ensureVisible\(',
    'un second défilement par pas ; dpad ramène la cible à l’écran',
  ),
  'TvFocusLegacy': (
    r'\bTvFocus(Memory|Panes|Pane|Rows|Row)\(|\bTvFocus(Entries|Scroll)\.',
    'l’ancien système de zones, que TvRegion remplace',
  ),
};

/// Les dossiers du nouveau système : ce test ne les regarde pas.
const List<String> _home = <String>['lib/tv/nav/', 'lib/tv/input/'];

/// L'existant au début de la migration (phase 1), et ce qu'il reste à
/// migrer : fichier → construit → nombre d'occurrences.
///
/// Phase 2 : les rangées du shell (`shell_tab_stack`, `media_row`,
/// `poster_rail`, `detail_cast_section`, `season_bubbles`) sont passées à
/// `TvRegion`. `main.dart` et `shell_header_zone.dart` gardent leurs entrées
/// tant que le drapeau `ONYX_TV_NAV` existe : la politique de parcours et l'action des
/// flèches de l'ancien système y sont encore montées quand il vaut `legacy`.
///
/// Phase 3 : les réglages (`settings_screen`, sur `TvRegion.panes`), les
/// épisodes (`episode_tile`, sur `TvFocusable.onDirection`) et le bandeau
/// (`hero_carousel`, sur `TvRegion.slide`) sont sortis. Ce qui reste des
/// écrans de la phase 3 n'est pas de la navigation : la touche lecture/pause
/// du bandeau « Reprendre » (`remote_playback_banner`), le suivi de la bulle
/// qui grandit (`season_bubbles`, un défilement à la fin de l'animation, pas
/// par flèche), le défilement du texte d'un document (`legal_document_screen`)
/// et le zoom de la grille au clavier (`poster_grid_zoom_region`).
///
/// **La liste ne fait que rétrécir.** Un fichier qui y figure n'en gagne pas
/// une de plus ; un fichier qui en perd voit son plafond baissé dans le même
/// changement (le second test l'exige), pour qu'il ne puisse plus y remonter.
/// Y relever un plafond « pour que le test passe » est exactement ce que ce
/// test existe pour empêcher. Elle doit être vide à la fin de la phase 8, hors
/// les entrées qui ne sont pas de la navigation (curseurs de valeur,
/// raccourcis du lecteur, `routePlayerKey`), chacune avec sa raison.
const Map<String, Map<String, int>> _legacy = {
  'lib/main.dart': {
    'DirectionalFocus': 1,
    'FocusTraversalGroup': 1,
    'Shortcuts': 1,
    'TraversalPolicy': 1,
  },
  'lib/screens/auth/login_password_field.dart': {
    'Shortcuts': 1,
  },
  'lib/screens/player/hooks/use_player_popup.dart': {
    'onKeyEvent': 1,
  },
  'lib/screens/player/playback/still_watching.dart': {
    'KeyboardHandler': 1,
  },
  'lib/screens/player/player_screen.dart': {
    'onKeyEvent': 1,
  },
  'lib/screens/player/widgets/onyx/onyx_progress_bar.dart': {
    'onKeyEvent': 1,
  },
  'lib/screens/player/widgets/onyx/onyx_settings_menu.dart': {
    'onKeyEvent': 1,
  },
  'lib/screens/player/widgets/player_episodes_panel.dart': {
    'ensureVisible': 1,
  },
  'lib/screens/settings/legal_document_screen.dart': {
    'onKeyEvent': 1,
  },
  // Sorti de main_shell.dart en phase 2, à l'identique, pour que les cartes
  // de navigation l'éprouvent : déplacé, pas ajouté.
  'lib/screens/shell/shell_header_zone.dart': {
    'FocusTraversalGroup': 1,
    'TraversalPolicy': 2,
    'TvFocusLegacy': 2,
  },
  'lib/tv/tv_focus.dart': {
    'DirectionalFocus': 4,
    'KeyboardHandler': 1,
    'TvFocusLegacy': 5,
    'ensureVisible': 1,
    'onKeyEvent': 1,
  },
  'lib/tv/tv_focus_entry.dart': {
    'TraversalPolicy': 6,
    'TvFocusLegacy': 3,
  },
  'lib/tv/tv_focus_guard.dart': {
    'KeyboardHandler': 1,
  },
  'lib/tv/tv_focus_memory.dart': {
    'TvFocusLegacy': 3,
  },
  'lib/tv/tv_focus_panes.dart': {
    'TvFocusLegacy': 2,
  },
  'lib/tv/tv_focus_rows.dart': {
    'TvFocusLegacy': 2,
    'onKeyEvent': 2,
  },
  'lib/tv/tv_focus_scroll.dart': {
    'TraversalPolicy': 1,
    'ensureVisible': 2,
  },
  'lib/tv/tv_key_repeat.dart': {
    'DirectionalFocus': 2,
    'KeyboardHandler': 1,
    'TvFocusLegacy': 2,
  },
  'lib/tv/tv_touchpad.dart': {
    'DirectionalFocus': 2,
    'KeyboardHandler': 2,
  },
  'lib/tv/web_tv_field_exit.dart': {
    'KeyboardHandler': 1,
  },
  'lib/widgets/global/app_slider.dart': {
    'onKeyEvent': 1,
  },
  'lib/widgets/global/interface_tour/tour_anchor.dart': {
    'ensureVisible': 1,
  },
  'lib/widgets/global/poster_grid_zoom_region.dart': {
    'KeyboardHandler': 1,
  },
  'lib/widgets/global/remote_playback_banner.dart': {
    'KeyboardHandler': 1,
  },
  'lib/widgets/global/season_bubbles.dart': {
    'ensureVisible': 1,
  },
};

/// Ce qui traite Retour soi-même : un `PopScope` (ou ses cousins), une touche
/// Retour lue à la main.
final RegExp _ownBackPattern = RegExp(
  r'\b(PopScope|WillPopScope|NavigatorPopHandler)\s*(<[^>(]*>)?\(|'
  r'\bisSelfHandledBackKey\(|\bkTvBackKeys\b|'
  r'\bLogicalKeyboardKey\.(escape|goBack|browserBack|gameButtonB)\b',
);

/// Ceux qui traitent Retour eux-mêmes, hors de `TvBack` (phase 5) : fichier
/// → (occurrences, pourquoi). Sous dpad, `TvBack` décide seul ; un `PopScope`
/// n'y est admis que si `TvBack` l'atteint par le `maybePop` du navigateur
/// racine, et une touche lue à la main que si elle passe par
/// `TvBack.claimKey`, qui la dédoublonne d'avec `popRoute`.
///
/// **La liste ne fait que rétrécir**, comme [_legacy].
const Map<String, (int, String)> _ownBack = {
  'lib/tv/tv_focus.dart': (
    11,
    'les touches Retour de l’ancien système (kTvBackKeys, raccourcis, '
        'TvBackAction) ; partent avec le drapeau ONYX_TV_NAV',
  ),
  'lib/screens/shell/shell_tv_back.dart': (
    1,
    'le PopScope de l’ancien système, à l’identique ; sous dpad, la coquille '
        'est une marche de TvBack (TvBackStep)',
  ),
  'lib/screens/shell/main_shell.dart': (
    1,
    'NavigatorPopHandler des fiches hors téléviseur (sur téléviseur, pas de '
        'navigateur imbriqué) ; TvBack l’atteindrait par maybePop',
  ),
  'lib/screens/shared_link/shared_link_guest.dart': (
    1,
    'PopScope du navigateur imbriqué d’un lien partagé : TvBack l’atteint par '
        'maybePop, il dépile chez lui sans décider de la racine',
  ),
  'lib/screens/player/player_screen.dart': (
    1,
    'lecteur, migré en phase 7 : son PopScope reçoit popRoute par TvBack',
  ),
  'lib/screens/player/player_key_routing.dart': (
    1,
    'lecteur, phase 7 : la touche est lue avant dpad (C4), et l’action '
        'passe par TvBack.claimKey',
  ),
  'lib/screens/player/hooks/use_player_popup.dart': (
    1,
    'menus du lecteur (pas des routes), phase 7 : TvBack.claimKey',
  ),
  'lib/screens/player/widgets/onyx/onyx_settings_menu.dart': (
    1,
    'remontée d’une section du menu du lecteur, phase 7 : TvBack.claimKey',
  ),
};

Map<String, int> _ownBackCensus() => {
      for (final (path, code) in _sources())
        if (!_home.any(path.startsWith) &&
            _ownBackPattern.allMatches(code).isNotEmpty)
          path: _ownBackPattern.allMatches(code).length,
    };

/// Ce que dpad expose et que seul `lib/tv/` emploie : les écrans n'ont que
/// `TvFocusable` et `TvRegion`. Une montée de version de dpad se fait alors à
/// un seul endroit.
final RegExp _dpadApi = RegExp(
  r'''\bDpad(Focusable|Region|RegionState)\b|\bDpad\.(of|maybeOf|wrap|keySetOf)\b|package:dpad/''',
);

/// Le seul `Dpad` de l'app (plan §3 : « un seul Dpad »).
final RegExp _dpadRoot = RegExp(r'\bDpad(\.wrap)?\(');
const String _dpadRootHome = 'lib/tv/nav/onyx_dpad.dart';

/// Les `TvFocusable` sans `onSelect`, et pourquoi ils n'en ont pas besoin.
///
/// Sur dpad, l'enfant d'un `TvFocusable` ne prend plus le focus : un bouton
/// ou un `InkWell` enveloppé ne reçoit plus OK, et seule l'action passée en
/// `onSelect` part à la télécommande (constat N4 du rapport de phase 0). Un
/// `TvFocusable` sans `onSelect` ne fait donc que montrer le focus.
const Map<String, String> _focusOnly = {
  'lib/screens/settings/pages/stats_page.dart':
      'les barres du graphique : le focus désigne le jour, OK n’a rien à faire',
};

/// Les commentaires citent les anciens widgets sans les employer.
String _code(String source) => source.split('\n').map((line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    }).join('\n');

Iterable<(String path, String code)> _sources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // La liste est écrite en barres obliques ; Windows rend des barres
    // inverses.
    final path = entity.path.replaceAll('\\', '/');
    yield (path, _code(entity.readAsStringSync()));
  }
}

Map<String, Map<String, int>> _census() {
  final census = <String, Map<String, int>>{};
  for (final (path, code) in _sources()) {
    if (_home.any(path.startsWith)) continue;
    for (final MapEntry(key: name, value: (pattern, _))
        in _constructs.entries) {
      final count = RegExp(pattern).allMatches(code).length;
      if (count > 0) (census[path] ??= <String, int>{})[name] = count;
    }
  }
  return census;
}

/// Le recensement sous la forme de [_legacy], pour le recopier.
String _asDart(Map<String, Map<String, int>> census) {
  final paths = census.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final path in paths) {
    final entries = census[path]!.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    buffer.writeln("  '$path': {");
    for (final entry in entries) {
      buffer.writeln("    '${entry.key}': ${entry.value},");
    }
    buffer.writeln('  },');
  }
  return buffer.toString();
}

void main() {
  test('aucun second système de focus n’apparaît à côté de dpad', () {
    final offenders = <String>[];
    _census().forEach((path, counts) {
      counts.forEach((name, count) {
        final ceiling = _legacy[path]?[name] ?? 0;
        if (count > ceiling) {
          offenders.add('$path : $name × $count (toléré : $ceiling) — '
              '${_constructs[name]!.$2}');
        }
      });
    });

    expect(
      offenders,
      isEmpty,
      reason: 'La navigation TV a un seul système de focus, dpad (ADR-0110). '
          'Un écran prend TvFocusable et TvRegion (lib/tv/nav/) ; une flèche '
          'qui doit être retenue ou multipliée passe par TvArrowGate '
          '(lib/tv/input/), un Retour par TvBack. Ajouter un mécanisme à côté, '
          'c’est revenir aux deux requestFocus et aux deux défilements par '
          'flèche que la refonte supprime :\n\n${offenders.join('\n')}\n\n'
          'Voir docs/refonte-navigation-dpad.md §3.',
    );
  });

  test('la liste de l’existant ne fait que rétrécir', () {
    final census = _census();
    final stale = <String>[];
    _legacy.forEach((path, ceilings) {
      if (!File(path).existsSync()) {
        stale.add('$path n’existe plus : retirez-le');
        return;
      }
      ceilings.forEach((name, ceiling) {
        final count = census[path]?[name] ?? 0;
        if (count < ceiling) {
          stale.add('$path : $name × $count, plafond $ceiling → '
              '${count == 0 ? 'retirez l’entrée' : 'baissez-le à $count'}');
        }
      });
    });
    expect(
      stale,
      isEmpty,
      reason: 'Un plafond au-dessus de l’existant est une porte laissée '
          'ouverte : le prochain changement pourrait y remettre ce que la '
          'migration vient d’enlever.\n\n${stale.join('\n')}\n\n'
          'Recensement actuel, à recopier dans _legacy :\n${_asDart(census)}',
    );
  });

  test('un seul Retour : TvBack', () {
    final census = _ownBackCensus();
    final offenders = <String>[];
    final stale = <String>[];
    census.forEach((path, count) {
      final ceiling = _ownBack[path]?.$1 ?? 0;
      if (count > ceiling) {
        offenders.add('$path × $count (toléré : $ceiling)');
      }
    });
    _ownBack.forEach((path, entry) {
      final count = census[path] ?? 0;
      if (count < entry.$1) {
        stale.add('$path × $count, plafond ${entry.$1} → '
            '${count == 0 ? 'retirez l’entrée' : 'baissez-le à $count'}');
      }
    });
    expect(
      offenders,
      isEmpty,
      reason: 'Sous dpad, TvBack est le seul à décider du Retour (ADR-0110, '
          'phase 5) : popRoute et touche, dédoublonnés, et rendu au système '
          'à la racine. Un PopScope ou une touche Retour lue à côté, c’est '
          'un double Retour sur Android, ou Menu retenu à la racine sur '
          'Apple TV (refus de l’App Review). Passez par TvBackStep, ou par '
          'TvBack.claimKey pour une touche lue avant dpad, ou inscrivez dans '
          '_ownBack pourquoi :\n\n${offenders.join('\n')}',
    );
    expect(
      stale,
      isEmpty,
      reason: 'La liste _ownBack ne fait que rétrécir :\n\n${stale.join('\n')}',
    );
  });

  test('dpad ne s’emploie qu’à l’intérieur de lib/tv/', () {
    final offenders = [
      for (final (path, code) in _sources())
        if (!path.startsWith('lib/tv/') && _dpadApi.hasMatch(code)) path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'DpadFocusable, DpadRegion, Dpad.of et l’import de dpad '
          'restent dans lib/tv/ : les écrans voient TvFocusable et TvRegion, '
          'et une montée de version de dpad (dont l’API bouge encore) se '
          'fait à un seul endroit.\n\n${offenders.join('\n')}',
    );
  });

  test('un seul Dpad dans l’app', () {
    final offenders = [
      for (final (path, code) in _sources())
        if (path != _dpadRootHome && _dpadRoot.hasMatch(code)) path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'OnyxDpad est le seul Dpad : il corrige le double Retour '
          'd’Android, le mode non-TV et le focus à la reprise. Un second '
          'Dpad ne se justifie que pour le chrome du lecteur, et seulement '
          'avec une ADR (plan §3).\n\n${offenders.join('\n')}',
    );
  });

  test('chaque TvFocusable porte son action en onSelect (N4)', () {
    final offenders = <String>[];
    for (final (path, code) in _sources()) {
      if (path.startsWith('lib/tv/') || _focusOnly.containsKey(path)) continue;
      for (final match in RegExp(r'\bTvFocusable\(').allMatches(code)) {
        if (!_arguments(code, match.end).contains(RegExp(r'\bonSelect:'))) {
          final line = '\n'.allMatches(code.substring(0, match.start)).length;
          offenders.add('$path:${line + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Sur dpad, l’enfant d’un TvFocusable ne reçoit plus OK : un '
          'bouton enveloppé garde son onPressed au toucher, mais la '
          'télécommande n’appelle que onSelect (constat N4). Passez-lui '
          'l’action, ou inscrivez dans _focusOnly pourquoi il n’en a pas :'
          '\n\n${offenders.join('\n')}',
    );
    for (final path in _focusOnly.keys) {
      expect(File(path).existsSync(), isTrue, reason: '$path n’existe plus');
    }
  });
}

/// Le texte entre la parenthèse ouvrante (juste avant [start]) et sa
/// fermante.
String _arguments(String code, int start) {
  var depth = 1;
  var i = start;
  while (depth > 0 && i < code.length) {
    final char = code[i];
    if (char == '(') depth++;
    if (char == ')') depth--;
    i++;
  }
  return code.substring(start, i);
}
