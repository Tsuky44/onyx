import 'tr.dart';

/// Le nom d'un genre TMDB dans la langue de l'app.
///
/// Le serveur garde l'identifiant, qui ne dépend pas de la langue (« Mes
/// stats », voir l'ADR 2026-11-26-tsuky-statistiques-personnelles). Les genres
/// doubles des séries (« Sci-Fi & Fantasy »…) arrivent déjà repliés sur ceux
/// des films ; ils restent nommés ici pour un serveur qui ne le ferait pas.
/// Un genre que TMDB ajouterait un jour n'a pas de nom : nul, il ne s'affiche
/// pas.
String? tmdbGenreLabel(int id) => switch (id) {
      28 => tr('Action'),
      12 => tr('Aventure'),
      16 => tr('Animation'),
      35 => tr('Comédie'),
      80 => tr('Crime'),
      99 => tr('Documentaire'),
      18 => tr('Drame'),
      10751 => tr('Familial'),
      14 => tr('Fantastique'),
      36 => tr('Histoire'),
      27 => tr('Horreur'),
      10402 => tr('Musique'),
      9648 => tr('Mystère'),
      10749 => tr('Romance'),
      878 => tr('Science-fiction'),
      10770 => tr('Téléfilm'),
      53 => tr('Thriller'),
      10752 => tr('Guerre'),
      37 => tr('Western'),
      10759 => tr('Action et aventure'),
      10765 => tr('Science-fiction et fantastique'),
      10768 => tr('Guerre et politique'),
      10762 => tr('Enfants'),
      10763 => tr('Actualités'),
      10764 => tr('Téléréalité'),
      10766 => tr('Feuilleton'),
      10767 => tr('Talk-show'),
      _ => null,
    };
