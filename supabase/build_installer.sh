#!/usr/bin/env bash
# Assemble les migrations en un seul fichier à coller dans Supabase > SQL Editor.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
{
  echo "-- ====================================================================="
  echo "-- SOUKI DEALS — INSTALLATEUR COMPLET (à coller dans Supabase > SQL Editor > Run)"
  echo "-- Réinstalle toute la base de test. Les comptes utilisateurs sont conservés."
  echo "-- ====================================================================="
  echo "begin;"
  for f in "$HERE"/migrations/*.sql; do echo; echo "-- >>> $(basename "$f")"; cat "$f"; done
  echo
  echo "commit;"
} > "$HERE/INSTALLER_SOUKI_DEALS.sql"
