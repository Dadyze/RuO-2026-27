#!/usr/bin/env bash
# s6/p4: backup i test restore-a za bazu iz s6/p3, prema politici iz politika.env.
#
#   ./backup.sh backup      jedan backup: pg_dump, kontrolni zbir, retencija, kopija u S3 (ako Garage radi)
#   ./backup.sh serija      politika + četiri backupa s prometom između njih (vidi se retencija)
#   ./backup.sh lista       lokalni backupi i kopije u S3
#   ./backup.sh restore     kvar, test restore-a u izolovanu instancu, oporavak, mjerenje RPO i RTO
#   ./backup.sh obrisi      briše backupe i restore instancu
set -euo pipefail
cd "$(dirname "$0")"
source ../okruzenje.sh
source politika.env

BK="$LAB/backup"
RI="$LAB/pg/restore"
S3ENV="$LAB/garage/s3.env"

s3_radi() { [ -f "$S3ENV" ] && [ -f "$LAB/garage/pid" ] && kill -0 "$(cat "$LAB/garage/pid")" 2>/dev/null; }
s3() { ( set -a; source "$S3ENV"; set +a; python3 ../p2/s3.py "$@" ); }
treba_primarni() { pg_radi "$LAB/pg/primarni" || { echo "Baza ne radi: make s6-p3"; exit 1; }; }
broj() { DB=$BAZA psql_admin "$1" -tAc "SELECT count(*) FROM prodaja.narudzbe" 2>/dev/null || echo "nema tabele"; }
sad() { date +%s.%N; }
traje() { awk -v a="$1" -v b="$(sad)" 'BEGIN{printf "%.1f", b-a}'; }
promet() { # n narudžbi preko aplikacijskog korisnika
  psql_kao app "$PG_PRIMARNI" -tAc "INSERT INTO prodaja.narudzbe (kupac_id, iznos)
    SELECT 1 + (g % 3), round((10 + random() * 90)::numeric, 2) FROM generate_series(1, $1) g" >/dev/null
}

backup() {
  nije_root; treba_pg; treba_primarni
  mkdir -p "$BK"; chmod 700 "$BK"
  local ime f; ime="$BAZA-$(date +%Y%m%d-%H%M%S).dump"; f="$BK/$ime"
  # -Fc: komprimovani "custom" format; pg_restore iz njega može vratiti sve ili samo dio (jednu tabelu)
  echo "\$ pg_dump -h 127.0.0.1 -p $PG_PRIMARNI -U backup -Fc -f $ime $BAZA"
  PGPASSWORD="$(lozinka backup)" "$PGBIN/pg_dump" -h 127.0.0.1 -p "$PG_PRIMARNI" -U backup -Fc -f "$f" "$BAZA"
  (cd "$BK" && sha256sum "$ime" > "$ime.sha256")
  echo "  $ime  $(du -h "$f" | cut -f1)  narudžbi: $(broj "$PG_PRIMARNI")  sha256: $(cut -c1-16 "$f.sha256")..."
  # retencija: zadržati zadnjih ZADRZI, starije obrisati (ls -t: najnoviji prvi)
  ls -1t "$BK"/*.dump | tail -n +$((ZADRZI + 1)) | while read -r star; do
    rm -f "$star" "$star.sha256"; echo "  retencija (ZADRZI=$ZADRZI): obrisan $(basename "$star")"
  done
  if s3_radi; then
    s3 put "$S3_BUCKET" "$S3_PREFIKS$ime" "$f" >/dev/null && s3 put "$S3_BUCKET" "$S3_PREFIKS$ime.sha256" "$f.sha256" >/dev/null
    echo "  kopija izvan servera: s3://$S3_BUCKET/$S3_PREFIKS$ime"
  else
    echo "  (Garage ne radi: nema kopije izvan servera; make s6-p2 je pokreće)"
  fi
}

serija() {
  korak "Politika (s6/p4/politika.env)"
  grep -E '^[A-Z]' politika.env | sed 's/^/  /'
  for i in 1 2 3 4; do
    korak "Backup $i/4 (prije njega: promet od 5 narudžbi)"
    promet 5; backup; sleep 1
  done
  lista
}

lista() {
  korak "Lokalni backupi ($BK)"
  ls -1t "$BK"/*.dump 2>/dev/null | while read -r f; do echo "  $(basename "$f")  $(du -h "$f" | cut -f1)"; done
  if s3_radi; then korak "Kopije u S3 (s3://$S3_BUCKET/$S3_PREFIKS)"; s3 ls "$S3_BUCKET" "$S3_PREFIKS"; fi
}

restore() {
  nije_root; treba_pg; treba_primarni
  local zadnji t_bk t0 izgubljeno rto_test rto rpo
  zadnji="$(ls -1t "$BK"/*.dump 2>/dev/null | head -1)"
  [ -n "$zadnji" ] || { echo "Nema backupa: make s6-p4"; exit 1; }
  t_bk="$(stat -c %Y "$zadnji")"

  korak "1. Stanje prije kvara: zadnji backup i promet nakon njega"
  echo "  zadnji backup: $(basename "$zadnji")"
  echo "  primarna: $(broj "$PG_PRIMARNI") narudžbi"
  promet 7
  echo "  + 7 novih narudžbi NAKON backupa -> primarna: $(broj "$PG_PRIMARNI")"
  local prije; prije="$(broj "$PG_PRIMARNI")"

  korak "2. Kvar: ljudska greška, DROP TABLE na primarnoj instanci"
  echo "\$ psql -c 'DROP TABLE prodaja.narudzbe CASCADE'"
  DB=$BAZA psql_admin "$PG_PRIMARNI" -c "SET client_min_messages=warning; DROP TABLE prodaja.narudzbe CASCADE"
  local t_kvar; t_kvar="$(sad)"
  echo "  primarna: $(broj "$PG_PRIMARNI")"
  if pg_radi "$LAB/pg/replika"; then
    sleep 0.5
    echo "  replika:  $(broj "$PG_REPLIKA")   <- replika je odmah ponovila grešku: replikacija NIJE backup"
  fi

  korak "3. Test restore-a u izolovanu instancu (127.0.0.1:$PG_RESTORE): da li se backup uopšte može vratiti?"
  t0="$(sad)"
  echo "\$ sha256sum -c $(basename "$zadnji").sha256"; (cd "$BK" && sha256sum -c "$(basename "$zadnji").sha256" | sed 's/^/  /')
  if pg_radi "$RI"; then "$PGBIN/pg_ctl" -D "$RI" -m fast stop >/dev/null; fi
  rm -rf "$RI"; nova_instanca "$RI"; pg_start "$RI" "$PG_RESTORE"
  echo "  initdb + start: prazna instanca"
  echo "  uloge nisu u pg_dump-u, pa se prvo primjenjuje kod iz s6/p3:"
  bash ../p3/baza.sh primijeni "$PG_RESTORE" sql/01-uloge.sql
  echo "\$ pg_restore -C -d postgres $(basename "$zadnji")"
  "$PGBIN/pg_restore" -h "$PG_SOCK" -p "$PG_RESTORE" -C -d postgres "$zadnji"
  echo "  provjera: narudžbi $(broj "$PG_RESTORE"); izvjestaj vidi promet: $(psql_kao izvjestaj "$PG_RESTORE" -tAc 'SELECT sum(narudzbi) FROM prodaja.v_promet_po_danu')"
  rto_test="$(traje "$t0")"
  echo "  test restore-a trajao: ${rto_test} s"
  "$PGBIN/pg_ctl" -D "$RI" -m fast stop >/dev/null; rm -rf "$RI"

  korak "4. Oporavak primarne instance iz istog backupa"
  echo "\$ dropdb --force $BAZA && pg_restore -C -d postgres $(basename "$zadnji")"
  "$PGBIN/dropdb" -h "$PG_SOCK" -p "$PG_PRIMARNI" --force "$BAZA"
  "$PGBIN/pg_restore" -h "$PG_SOCK" -p "$PG_PRIMARNI" -C -d postgres "$zadnji"
  rto="$(traje "$t_kvar")"
  echo "  primarna: $(broj "$PG_PRIMARNI") narudžbi"
  if pg_radi "$LAB/pg/replika"; then sleep 0.5; echo "  replika:  $(broj "$PG_REPLIKA") narudžbi (replika prati primarnu i kod oporavka)"; fi

  korak "5. RPO i RTO: šta smo izgubili i koliko je trajalo"
  izgubljeno=$((prije - $(broj "$PG_PRIMARNI")))
  rpo="$(awk -v a="$t_bk" -v b="$t_kvar" 'BEGIN{printf "%.0f", b-a}')"
  echo "  izgubljeno: $izgubljeno narudžbi = sve upisano nakon zadnjeg backupa"
  printf '  %-34s %8s   cilj: %s\n' "RPO (od zadnjeg backupa do kvara):" "${rpo} s" "<= $((RPO_CILJ_MIN * 60)) s ($RPO_CILJ_MIN min)"
  printf '  %-34s %8s   cilj: %s\n' "RTO (od kvara do rada baze):" "${rto} s" "<= $((RTO_CILJ_MIN * 60)) s ($RTO_CILJ_MIN min)"
  printf '  %-34s %8s\n' "od toga test restore-a:" "${rto_test} s"
  echo "  (gubitak smanjuje češći backup ili kontinuirano arhiviranje WAL-a: PITR, vidi bilješke)"
}

obrisi() {
  if pg_radi "$RI"; then "$PGBIN/pg_ctl" -D "$RI" -m fast stop >/dev/null; fi
  rm -rf "$BK" "$RI"
}

case "${1:-}" in
  backup) backup ;;
  serija) serija ;;
  lista) lista ;;
  restore) restore ;;
  obrisi) obrisi ;;
  *) echo "Upotreba: $0 backup | serija | lista | restore | obrisi"; exit 1 ;;
esac
