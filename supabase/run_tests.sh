#!/usr/bin/env bash
# Lance les tests de la base Souki sur un PostgreSQL local jetable.
# Usage : ./run_tests.sh   (nécessite PostgreSQL 15 ou plus)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /usr/lib/postgresql/16/bin/postgres)")}"
WORK="$(mktemp -d)"
PORT="${PG_PORT:-54329}"
trap '"$BIN/pg_ctl" -D "$WORK/data" stop -m fast >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

"$BIN/initdb" -D "$WORK/data" -U postgres -A trust >/dev/null
"$BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c timezone=UTC" -l "$WORK/log" start -w >/dev/null

PSQL=(psql -h "$WORK" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q -X)
"${PSQL[@]}" -f "$HERE/tests/simulation_supabase.sql" >/dev/null
"${PSQL[@]}" -f "$HERE/INSTALLER_SOUKI_DEALS.sql" >/dev/null
# Deuxième installation : vérifie que la remise à zéro fonctionne
"${PSQL[@]}" -f "$HERE/INSTALLER_SOUKI_DEALS.sql" >/dev/null
"${PSQL[@]}" -f "$HERE/tests/tests.sql"

# Base remplie par les tests : la mise à jour se relance sans rien perdre
BEFORE=$("${PSQL[@]}" -tA -c "select count(*) from public.invoices")
for f in MISE_A_JOUR_005_FACTURES MISE_A_JOUR_006_RELEVE MISE_A_JOUR_007_SCAN MISE_A_JOUR_008_INSCRITS MISE_A_JOUR_009_PROMOS MISE_A_JOUR_010_IBAN MISE_A_JOUR_011_COMPTE_NOTIFS MISE_A_JOUR_012_PHOTOS MISE_A_JOUR_013_NOTIFICATIONS MISE_A_JOUR_014_EMAILS MISE_A_JOUR_015_BIENVENUE_1000 MISE_A_JOUR_016_BON_OFFRE MISE_A_JOUR_017_INSCRITS; do
  "${PSQL[@]}" -f "$HERE/$f.sql" >/dev/null
  "${PSQL[@]}" -f "$HERE/$f.sql" >/dev/null
done
AFTER=$("${PSQL[@]}" -tA -c "select count(*) from public.invoices")
[ "$BEFORE" = "$AFTER" ] && [ "$AFTER" -gt 0 ] || { echo "ÉCHEC : la mise à jour a perdu des factures"; exit 1; }
echo "Mises à jour 005 à 017 relancées deux fois : $AFTER factures conservées"
# Factures émises : la remise à zéro doit être refusée
if "${PSQL[@]}" -f "$HERE/INSTALLER_SOUKI_DEALS.sql" >/dev/null 2>&1; then
  echo "ÉCHEC : remise à zéro acceptée alors que des factures existent"; exit 1
fi
echo "Remise à zéro refusée quand des factures existent : OK"
