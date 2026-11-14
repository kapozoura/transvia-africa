#!/bin/bash
# Rejoue la migration puis les tests sur un Postgres 16 local jetable.
# Usage : sudo -u postgres ./run_tests.sh   (ou en root : le script bascule sur l'utilisateur postgres)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
DB=transvia_test
PSQL="psql -v ON_ERROR_STOP=1 -q -X"
su postgres -c "psql -q -X -c 'drop database if exists $DB' -c 'create database $DB'"
for f in "$DIR/00_supabase_stub.sql" "$DIR/00b_roles_stub.sql" "$DIR"/../migrations/0001_compte_unique.sql "$DIR/01_compte_unique_test.sql" "$DIR"/../migrations/0002_covoiturage.sql "$DIR/02_covoiturage_test.sql"; do
  su postgres -c "$PSQL -d $DB -f '$f'" 2>&1 | grep -v "^$" || true
done
