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

# Mise à jour des bases déjà installées (n'efface rien, relançable)
{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 005 (factures des commissions). N'efface rien, relancable."
  cat "$HERE/migrations/005_factures.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_005_FACTURES.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 006 (conditions acceptees, releve annuel). N'efface rien, relancable."
  cat "$HERE/migrations/006_releve.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_006_RELEVE.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 007 (scan inverse : QR code du magasin). N'efface rien, relancable."
  cat "$HERE/migrations/007_scan_inverse.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_007_SCAN.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 008 (nombre d'inscrits). N'efface rien, relancable."
  cat "$HERE/migrations/008_inscrits.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_008_INSCRITS.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 009 (offre de bienvenue, promos des commercants). N'efface rien, relancable."
  cat "$HERE/migrations/009_promos.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_009_PROMOS.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 010 (IBAN des commercants). N'efface rien, relancable."
  cat "$HERE/migrations/010_iban.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_010_IBAN.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 011 (suppression du compte, notifications). N'efface rien, relancable."
  cat "$HERE/migrations/011_compte_notifications.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_011_COMPTE_NOTIFS.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 012 (photos des produits). N'efface rien, relancable."
  cat "$HERE/migrations/012_photos.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_012_PHOTOS.sql"

{
  echo "begin;"
  echo "-- SOUKI DEALS : mise a jour 013 (notifications completes). N'efface rien, relancable."
  cat "$HERE/migrations/013_notifications_completes.sql"
  echo
  echo "commit;"
} > "$HERE/MISE_A_JOUR_013_NOTIFICATIONS.sql"
