#!/usr/bin/env bash
# Assemble les migrations en un seul fichier à coller dans Supabase > SQL Editor.
# La première ligne est « begin; » (pas de commentaire en tête : certains copier-coller l'abîment).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
{
  echo "begin;"
  echo "-- SOUKI DEALS : installateur complet, a coller dans Supabase > SQL Editor > Run."
  for f in "$HERE"/migrations/*.sql; do echo; echo "-- >>> $(basename "$f")"; cat "$f"; done
  echo
  echo "commit;"
} > "$HERE/INSTALLER_SOUKI_DEALS.sql"
