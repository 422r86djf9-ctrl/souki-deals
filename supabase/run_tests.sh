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
