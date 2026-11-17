import 'package:flutter/services.dart';

import 'app_language.dart';

/// Le chemin de la traduction d'un fichier embarqué : `conditions.txt` devient
/// `conditions.en.txt`. Le fichier sans suffixe est le français, qui fait foi.
///
/// Un schéma dérivé plutôt qu'une table : ajouter l'espagnol ou l'allemand
/// revient à déposer `conditions.es.txt`, sans toucher au code.
String localizedAssetPath(String frenchPath, AppLanguage language) {
  if (language == AppLanguage.french) return frenchPath;
  final dot = frenchPath.lastIndexOf('.');
  final slash = frenchPath.lastIndexOf('/');
  if (dot <= slash) return '$frenchPath.${language.code}';
  return '${frenchPath.substring(0, dot)}.${language.code}'
      '${frenchPath.substring(dot)}';
}

/// Lit un texte embarqué dans la langue de l'app, ou en français si cette
/// langue n'a pas (encore) sa traduction.
Future<String> loadLocalizedAsset(
  String frenchPath, {
  AssetBundle? bundle,
  AppLanguage? language,
}) async {
  final assets = bundle ?? rootBundle;
  final path = localizedAssetPath(frenchPath, language ?? AppLanguage.current);
  if (path == frenchPath) return assets.loadString(frenchPath);
  try {
    return await assets.loadString(path);
  } catch (_) {
    // Une langue sans traduction de ce texte montre la version qui fait foi :
    // mieux vaut le français qu'un écran d'erreur.
    return assets.loadString(frenchPath);
  }
}
