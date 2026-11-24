#!/usr/bin/env bash
# =============================================================================
# Onyx : la version d'une publication, calculee a partir de ce qui est sorti
# =============================================================================
# Usage (depuis un clone qui a tous ses tags : fetch-depth 0) :
#   scripts/ci/resolve-version.sh release <test|prod|major>
#       la version d'une publication globale (release.yml)
#   scripts/ci/resolve-version.sh platform <nom>
#       la version d'un build d'une seule plateforme (tvos.yml : `tvos`)
#   scripts/ci/resolve-version.sh record <nom> <X.Y.Z>
#       note qu'une plateforme a publie cette version, et pousse la note
#   scripts/ci/resolve-version.sh latest-release
#       la derniere publication globale, pour le resume du run
#
# Deux sortes de tags disent ce qui est sorti :
#   vX.Y.Z               une publication globale (release.yml la cree)
#   build/<nom>/X.Y.Z    une plateforme publiee seule, sans publication globale
#
# Pourquoi. Une plateforme peut sortir seule (l'Apple TV sur TestFlight, par
# tvos.yml), et App Store Connect ferme une version des qu'elle est approuvee :
# le build suivant doit porter un numero plus haut. Tant que rien ne notait ce
# numero, la publication globale suivante le recalculait a partir du dernier
# tag vX.Y.Z, retombait sur la meme version que l'Apple TV, et Apple refusait
# son envoi (numero de build plus petit que celui deja recu). Il fallait s'en
# souvenir et taper la version a la main.
#
# La regle :
#   - une plateforme seule reste sur la version qu'elle a ouverte depuis la
#     derniere publication globale, sinon elle en ouvre une au-dessus de cette
#     publication ;
#   - une publication globale part de la version la plus haute connue, toutes
#     plateformes confondues, et tout le monde s'y aligne.
#
# Ecrit pour le bash 3.2 des runners macOS : ni tableau associatif, ni mapfile.
# =============================================================================

set -euo pipefail

usage() {
  sed -n '5,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

SEMVER='[0-9]+\.[0-9]+\.[0-9]+'

# La plus haute des versions lues sur l'entree, vide s'il n'y en a pas. Tri
# numerique champ par champ : un tri alphabetique placerait 1.0.9 apres 1.0.34.
highest() {
  { grep -E "^${SEMVER}\$" || true; } | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

# Vrai si $1 est strictement au-dessus de $2.
newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | highest)" = "$1" ]
}

bump() {
  local major minor patch
  IFS=. read -r major minor patch <<EOF
$1
EOF
  case "$2" in
    major) echo "$((major + 1)).0.0" ;;
    prod) echo "${major}.$((minor + 1)).0" ;;
    test) echo "${major}.${minor}.$((patch + 1))" ;;
    *)
      echo "::error::Niveau inconnu : '$2' (attendu : test, prod ou major)" >&2
      exit 2
      ;;
  esac
}

check_platform() {
  if ! printf '%s' "$1" | grep -Eq '^[a-z0-9]+$'; then
    echo "::error::Nom de plateforme invalide : '$1'" >&2
    exit 2
  fi
}

ALL_TAGS="$(git tag -l)"

release_versions() {
  printf '%s\n' "$ALL_TAGS" | sed -n -E "s#^v(${SEMVER})\$#\1#p"
}

# Les versions qu'une plateforme ($1, ou toutes) a publiees seule.
platform_versions() {
  printf '%s\n' "$ALL_TAGS" | sed -n -E "s#^build/${1:-[a-z0-9]+}/(${SEMVER})\$#\1#p"
}

LAST_RELEASE="$(release_versions | highest)"
LAST_RELEASE="${LAST_RELEASE:-0.0.0}"

case "${1:-}" in
  latest-release)
    echo "$LAST_RELEASE"
    ;;

  release)
    [ $# -eq 2 ] || usage
    base="$({ release_versions; platform_versions; } | highest)"
    bump "${base:-0.0.0}" "$2"
    ;;

  platform)
    [ $# -eq 2 ] || usage
    check_platform "$2"
    own="$(platform_versions "$2" | highest)"
    if [ -n "$own" ] && newer "$own" "$LAST_RELEASE"; then
      echo "$own"
    else
      bump "$LAST_RELEASE" test
    fi
    ;;

  record)
    [ $# -eq 3 ] || usage
    check_platform "$2"
    if ! printf '%s' "$3" | grep -Eq "^${SEMVER}\$"; then
      echo "::error::Version invalide : '$3' (format attendu : X.Y.Z)" >&2
      exit 2
    fi
    tag="build/$2/$3"
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      echo "Deja note : $tag"
      exit 0
    fi
    git tag "$tag"
    git push origin "refs/tags/$tag"
    echo "Note : $tag"
    ;;

  *)
    usage
    ;;
esac
