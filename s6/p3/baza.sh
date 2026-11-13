#!/usr/bin/env bash
# s6/p3: PostgreSQL kao kod: instanca, uloge, shema i privilegije iz datoteka (sql/), te replika.
# Instance rade kao procesi korisnika na 127.0.0.1 (primarna 5461, replika 5462), podaci u s6/.lab/pg.
#
#   ./baza.sh up          primarna instanca + SQL kod primijenjen dva puta (idempotentnost)
#   ./baza.sh test        privilegije: šta app i izvjestaj smiju, a šta ne
#   ./baza.sh replika     replika (pg_basebackup) i provjera replikacije
#   ./baza.sh status      stanje instanci
#   ./baza.sh down        gasi instance (podaci ostaju; ./baza.sh obrisi briše sve)
set -euo pipefail
cd "$(dirname "$0")"
source ../okruzenje.sh

P="$LAB/pg/primarni"
R="$LAB/pg/replika"

# lab lozinke: nasumične, prave se jednom i nisu u Gitu
lozinke() {
  [ -f "$LAB/pg/lozinke.env" ] && return 0
  mkdir -p "$LAB/pg"; umask 077
  for u in app izvjestaj repl backup; do echo "$u=$(openssl rand -hex 12)"; done > "$LAB/pg/lozinke.env"
}
sql_varijable() { for u in app izvjestaj repl backup; do printf -- '-v %s_lozinka=%s ' "$u" "$(lozinka "$u")"; done; }

# primjena SQL koda: sve datoteke redom (ili samo zadane), uvijek isti ishod
primijeni() { # port [datoteke...]
  local port="$1"; shift
  local datoteke=("$@") x; [ ${#datoteke[@]} -gt 0 ] || datoteke=(sql/0*.sql)
  for x in "${datoteke[@]}"; do echo "  psql -f $x"; psql_admin "$port" $(sql_varijable) -f "$x"; done
}

# "otisak" stanja: uloge (bez lozinki) + shema i privilegije; isti otisak = ista baza
otisak() {
  { "$PGBIN/pg_dumpall" -h "$PG_SOCK" -p "$1" --roles-only --no-role-passwords
    "$PGBIN/pg_dump" -h "$PG_SOCK" -p "$1" --schema-only prodavnica; } 2>/dev/null | grep -vE '^(--|\\(un)?restrict)' | md5sum | cut -c1-12
}

gore() {
  nije_root; treba_pg; lozinke; mkdir -p "$PG_SOCK"
  korak "1. Instanca: initdb (prazan klaster) + pg_hba.conf i postavke iz repozitorija"
  if [ -f "$P/PG_VERSION" ]; then echo "  postoji: $P"; else nova_instanca "$P"; echo "  initdb -> $P (PostgreSQL $(cat "$P/PG_VERSION"))"; fi
  pg_radi "$P" || pg_start "$P" "$PG_PRIMARNI"
  echo "  radi na 127.0.0.1:$PG_PRIMARNI"

  korak "2. Prva primjena SQL koda (uloge, baza, shema, privilegije)"
  primijeni "$PG_PRIMARNI"
  echo "  otisak stanja: $(otisak "$PG_PRIMARNI")"

  korak "3. Ponovna primjena istog koda: otisak mora ostati isti (idempotentnost)"
  primijeni "$PG_PRIMARNI"
  echo "  otisak stanja: $(otisak "$PG_PRIMARNI")"

  korak "4. Uloge i njihova svojstva (\\du)"
  psql_admin "$PG_PRIMARNI" -c '\du'
}

ok_ili_greska() { # opis, pa naredba: ispisuje DOZVOLJENO ili ODBIJENO s porukom servera
  local opis="$1"; shift
  local izlaz; if izlaz="$("$@" 2>&1)"; then printf '  %-52s DOZVOLJENO %s\n' "$opis" "$(tr '\n' ' ' <<<"$izlaz")"
  else printf '  %-52s ODBIJENO   %s\n' "$opis" "$(grep -m1 -oE '(ERROR|FATAL|psql: error).*' <<<"$izlaz" | sed -E 's/.*(ERROR|FATAL): *//')"; fi
}

test_() {
  pg_radi "$P" || { echo "Primarna instanca ne radi: make s6-p3"; exit 1; }
  local A="-v ON_ERROR_STOP=1 -tA -c"
  korak "1. app (aplikacija): čita i piše svoje tabele"
  ok_ili_greska "app: INSERT INTO narudzbe" psql_kao app "$PG_PRIMARNI" $A \
    "INSERT INTO prodaja.narudzbe (kupac_id, iznos) SELECT id, 25.50 FROM prodaja.kupci WHERE email='amra@ruo.lab' RETURNING 'id=' || id"
  ok_ili_greska "app: SELECT count(*) FROM narudzbe" psql_kao app "$PG_PRIMARNI" $A "SELECT count(*) FROM prodaja.narudzbe"
  korak "2. app ne smije brisati redove ni mijenjati strukturu (nije vlasnik)"
  ok_ili_greska "app: DELETE FROM narudzbe" psql_kao app "$PG_PRIMARNI" $A "DELETE FROM prodaja.narudzbe"
  ok_ili_greska "app: DROP TABLE narudzbe" psql_kao app "$PG_PRIMARNI" $A "DROP TABLE prodaja.narudzbe"
  ok_ili_greska "app: CREATE TABLE u public shemi" psql_kao app "$PG_PRIMARNI" $A "CREATE TABLE public.x (a int)"
  korak "3. izvjestaj: vidi samo zbirni pogled, ne i kupce (lični podaci)"
  ok_ili_greska "izvjestaj: SELECT v_promet_po_danu" psql_kao izvjestaj "$PG_PRIMARNI" $A "SELECT dan || ' ' || narudzbi || ' ' || promet FROM prodaja.v_promet_po_danu"
  ok_ili_greska "izvjestaj: SELECT email FROM kupci" psql_kao izvjestaj "$PG_PRIMARNI" $A "SELECT email FROM prodaja.kupci"
  ok_ili_greska "izvjestaj: INSERT INTO narudzbe" psql_kao izvjestaj "$PG_PRIMARNI" $A "INSERT INTO prodaja.narudzbe (kupac_id, iznos) VALUES (1, 1)"
  korak "4. pg_hba.conf i lozinke: pogrešna baza, pogrešna lozinka, uloga samo za replikaciju"
  DB=postgres ok_ili_greska "app -> baza postgres (nije u pg_hba)" psql_kao app "$PG_PRIMARNI" $A "SELECT 1"
  ok_ili_greska "app s pogrešnom lozinkom" env PGPASSWORD=pogresna "$PGBIN/psql" -X -h 127.0.0.1 -p "$PG_PRIMARNI" -U app -d prodavnica $A "SELECT 1"
  ok_ili_greska "repl -> baza prodavnica (samo replikacija)" env PGPASSWORD="$(lozinka repl)" "$PGBIN/psql" -X -h 127.0.0.1 -p "$PG_PRIMARNI" -U repl -d prodavnica $A "SELECT 1"
}

replika() {
  nije_root; treba_pg
  pg_radi "$P" || { echo "Primarna instanca ne radi: make s6-p3"; exit 1; }
  korak "1. Replika: pg_basebackup kopira primarnu instancu i pravi replikacijski slot"
  if [ -f "$R/PG_VERSION" ]; then echo "  postoji: $R"
  else
    echo "\$ pg_basebackup -h 127.0.0.1 -p $PG_PRIMARNI -U repl -D $R -R -X stream -C -S replika1"
    PGPASSWORD="$(lozinka repl)" "$PGBIN/pg_basebackup" -h 127.0.0.1 -p "$PG_PRIMARNI" -U repl -D "$R" -R -X stream -C -S replika1
    echo "  -R je napisao standby.signal i primary_conninfo (postgresql.auto.conf):"
    grep -oE "primary_conninfo = '(\S+ ){3}\S+" "$R/postgresql.auto.conf" | sed -E 's/password=\S+/password=*****/; s/^/    /' || true
  fi
  pg_radi "$R" || pg_start "$R" "$PG_REPLIKA"
  echo "  replika radi na 127.0.0.1:$PG_REPLIKA"

  korak "2. Primarna instanca vidi repliku (pg_stat_replication)"
  for _ in $(seq 20); do [ -n "$(psql_admin "$PG_PRIMARNI" -tAc "SELECT 1 FROM pg_stat_replication WHERE state='streaming'")" ] && break; sleep 0.5; done
  psql_admin "$PG_PRIMARNI" -c "SELECT application_name, client_addr, state, sync_state, replay_lag FROM pg_stat_replication"
  echo "  replika: pg_is_in_recovery() = $(psql_admin "$PG_REPLIKA" -tAc 'SELECT pg_is_in_recovery()')"

  korak "3. Upis na primarnoj, čitanje na replici"
  local prije; prije="$(DB=prodavnica psql_admin "$PG_REPLIKA" -tAc 'SELECT count(*) FROM prodaja.narudzbe')"
  psql_kao app "$PG_PRIMARNI" -tAc "INSERT INTO prodaja.narudzbe (kupac_id, iznos) SELECT id, 99.90 FROM prodaja.kupci WHERE email='bojan@ruo.lab'" >/dev/null
  echo "  primarna: INSERT jedne narudžbe (app)"
  sleep 0.5
  echo "  replika:  narudžbi prije $prije, sada $(DB=prodavnica psql_admin "$PG_REPLIKA" -tAc 'SELECT count(*) FROM prodaja.narudzbe')"
  echo "  zaostatak replike: $(psql_admin "$PG_PRIMARNI" -tAc "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) FROM pg_stat_replication") bajta WAL-a"

  korak "4. Replika je samo za čitanje"
  ok_ili_greska "app: INSERT na replici" psql_kao app "$PG_REPLIKA" -v ON_ERROR_STOP=1 -tAc "INSERT INTO prodaja.narudzbe (kupac_id, iznos) VALUES (1, 1)"
  ok_ili_greska "izvjestaj: SELECT na replici" psql_kao izvjestaj "$PG_REPLIKA" -v ON_ERROR_STOP=1 -tAc "SELECT sum(narudzbi) FROM prodaja.v_promet_po_danu"
}

status() {
  for d in "$P:$PG_PRIMARNI" "$R:$PG_REPLIKA"; do
    if pg_radi "${d%%:*}"; then echo "  $(basename "${d%%:*}")  radi na 127.0.0.1:${d##*:}"; else echo "  $(basename "${d%%:*}")  ne radi"; fi
  done
}

dolje() {
  for d in "$R" "$P"; do pg_radi "$d" && "$PGBIN/pg_ctl" -D "$d" -m fast stop >/dev/null && echo "ugašena $(basename "$d")"; done
  return 0
}

case "${1:-}" in
  up) gore ;;
  test) test_ ;;
  replika) replika ;;
  status) status ;;
  down) [ -n "$PGBIN" ] && dolje ;;
  primijeni) shift; p="$1"; shift; lozinke; primijeni "$p" "$@" ;;   # za s6/p4: uloge na restore instanci
  *) echo "Upotreba: $0 up | test | replika | status | down"; exit 1 ;;
esac
