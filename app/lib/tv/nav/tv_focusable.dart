/// La cible de focus que les écrans emploient (ADR-0110).
///
/// Phase 1 de la refonte : la façade réexporte l'ancienne implémentation, à
/// l'identique. En phase 2, `TvFocusable` passe sur dpad (`TvDpadFocusable`,
/// même API) sans qu'un seul écran change de ligne.
library;

export '../tv_focus.dart'
    show TvFocusable, TvFocusHalo, kTvBackKeys, kTvSelectKeys;
