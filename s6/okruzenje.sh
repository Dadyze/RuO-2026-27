# s6: zajedničke postavke za primjere 2, 3 i 4 (učitava se naredbom: source ../okruzenje.sh).
# Garage i PostgreSQL rade kao obični procesi korisnika, na 127.0.0.1, s podacima u s6/.lab (nije u Gitu).
# Zato ne treba sudo, a make s6-clean briše sve.

S6="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$S6/.lab"

# PostgreSQL programi (initdb, pg_ctl ...) nisu u PATH-u na Ubuntuu: uzima se najnovija instalirana verzija
PGBIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"
PG_PRIMARNI=5461      # glavna instanca (čitanje i pisanje)
PG_REPLIKA=5462       # replika (samo čitanje, s6-p3-replika)
PG_RESTORE=5463       # izolovana instanca za test restore-a (s6-p4-restore)
PG_SOCK="$LAB/pg/sock"

korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
kmd() { echo "\$ $*"; "$@" || true; }

nije_root() {
  [ "$(id -u)" != 0 ] || { echo "Pokrenuti kao običan korisnik (bez sudo): Garage i PostgreSQL ovdje rade kao procesi korisnika."; exit 1; }
}
treba_pg() {
  [ -n "$PGBIN" ] && [ -x "$PGBIN/initdb" ] || { echo "PostgreSQL nije instaliran. Pokreni: ./00-setup.sh"; exit 1; }
}

# admin: OS korisnik preko unix socketa (peer autentifikacija, bez lozinke)
psql_admin() { local port="$1"; shift; "$PGBIN/psql" -X -q -h "$PG_SOCK" -p "$port" -d "${DB:-postgres}" -v ON_ERROR_STOP=1 "$@"; }
# aplikacijski korisnik: TCP + lozinka (scram-sha-256), kao što bi se spojila aplikacija
psql_kao() { # korisnik port [psql argumenti]
  local u="$1" port="$2"; shift 2
  PGPASSWORD="$(lozinka "$u")" "$PGBIN/psql" -X -q -h 127.0.0.1 -p "$port" -U "$u" -d "${DB:-prodavnica}" "$@"
}
lozinka() { awk -F= -v k="$1" '$1==k{print $2}' "$LAB/pg/lozinke.env" 2>/dev/null; }

# nova prazna instanca s pg_hba.conf i postavkama iz s6/p3 (koriste je primarna i restore instanca)
nova_instanca() { # data_dir
  "$PGBIN/initdb" -D "$1" -U "$(id -un)" --auth-local=peer --auth-host=scram-sha-256 -E UTF8 --no-locale >/dev/null
  cp "$S6/p3/pg_hba.conf" "$1/pg_hba.conf"
  echo "include '$S6/p3/postgresql.ruo.conf'" >> "$1/postgresql.conf"
}

pg_radi() { "$PGBIN/pg_ctl" -D "$1" status >/dev/null 2>&1; }
pg_start() { # data_dir port
  "$PGBIN/pg_ctl" -D "$1" -l "$1/server.log" -w -o "-p $2 -k $PG_SOCK" start >/dev/null
}
