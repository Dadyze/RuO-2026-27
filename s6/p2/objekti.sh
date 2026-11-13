#!/usr/bin/env bash
# s6/p2: object storage (S3) s Garageom: jedan čvor na 127.0.0.1, podaci u s6/.lab/garage.
#
#   ./objekti.sh up       konfiguracija, server, layout klastera, bucket i ključ (idempotentno)
#   ./objekti.sh test     S3 klijent (s3.py demo): put, list, head, get, presigned URL, odbijen pristup
#   ./objekti.sh status   stanje čvora i bucketa
#   ./objekti.sh down     gasi server (podaci ostaju; make s6-p2-clean briše i njih)
set -euo pipefail
cd "$(dirname "$0")"
source ../okruzenje.sh

DIR="$LAB/garage"
CFG="$DIR/garage.toml"
BUCKET=ruo-backup
KLJUC=ruo-backup-kljuc
g() { garage -c "$CFG" "$@"; }
gk() { echo "\$ garage $*"; g "$@" >/dev/null; }   # ispis naredbe, izlaz se ne prikazuje

radi() { [ -f "$DIR/pid" ] && kill -0 "$(cat "$DIR/pid")" 2>/dev/null; }

gore() {
  nije_root
  command -v garage >/dev/null || { echo "Nedostaje 'garage'. Pokreni: ./00-setup.sh"; exit 1; }
  mkdir -p "$DIR/meta" "$DIR/data"; chmod 700 "$DIR"

  korak "1. Konfiguracija iz repozitorija + tajne generisane lokalno (nisu u Gitu)"
  if [ ! -f "$CFG" ]; then
    sed -e "s|@DIR@|$DIR|g" -e "s|@RPC_SECRET@|$(openssl rand -hex 32)|" \
        -e "s|@ADMIN_TOKEN@|$(openssl rand -base64 24)|" garage.toml > "$CFG"
    chmod 600 "$CFG"
  fi
  grep -vE '^\s*(#|$)|secret|token' "$CFG" | sed 's/^/  /'

  korak "2. Server (garage server) u pozadini"
  if radi; then echo "  već radi (pid $(cat "$DIR/pid"))"
  else
    nohup garage -c "$CFG" server >"$DIR/server.log" 2>&1 &
    echo $! > "$DIR/pid"
    for _ in $(seq 40); do g status >/dev/null 2>&1 && break; sleep 0.25; done
    echo "  pokrenut (pid $(cat "$DIR/pid")), dnevnik: s6/.lab/garage/server.log"
  fi

  korak "3. Layout klastera: koji čvor drži koliko podataka i u kojoj zoni"
  if g layout show 2>/dev/null | grep -q 'dc1'; then echo "  layout već postoji"
  else
    NODE="$(g node id -q | cut -d@ -f1)"
    gk layout assign -z dc1 -c 1G "$NODE"
    gk layout apply --version 1
  fi
  g status | sed -n '/ID /,$p' | sed 's/^/  /'

  korak "4. Bucket i pristupni ključ s pravima samo na taj bucket (načelo najmanjih prava)"
  g bucket info "$BUCKET" >/dev/null 2>&1 || gk bucket create "$BUCKET"
  if ! g key info "$KLJUC" >/dev/null 2>&1; then echo "\$ garage key create $KLJUC"; g key create "$KLJUC" >/dev/null; fi
  gk bucket allow --read --write --owner "$BUCKET" --key "$KLJUC"
  local info id tajna
  info="$(g key info "$KLJUC" --show-secret)"
  id="$(grep -oE 'GK[0-9a-f]{24}' <<<"$info" | head -1)"
  tajna="$(grep -i 'secret' <<<"$info" | grep -oE '[0-9a-f]{64}' | head -1)"
  [ -n "$id" ] && [ -n "$tajna" ] || { echo "Ne mogu pročitati ključ iz 'garage key info':"; echo "$info"; exit 1; }
  umask 077
  cat > "$DIR/s3.env" <<EOF
S3_ENDPOINT=http://127.0.0.1:3900
AWS_DEFAULT_REGION=garage
AWS_ACCESS_KEY_ID=$id
AWS_SECRET_ACCESS_KEY=$tajna
AWS_REQUEST_CHECKSUM_CALCULATION=when_required
AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
EOF
  g bucket info "$BUCKET" | sed -n '/KEYS FOR THIS BUCKET/,$p' | sed 's/^/  /'
  echo "  ključ $id -> s6/.lab/garage/s3.env (tajna se ne ispisuje)"
}

test_() {
  radi || { echo "Garage ne radi: make s6-p2"; exit 1; }
  set -a; source "$DIR/s3.env"; set +a
  # nakon layout apply S3 API treba trenutak da prihvati zahtjeve
  for _ in $(seq 20); do python3 s3.py ls "$BUCKET" >/dev/null 2>&1 && break; sleep 0.5; done
  python3 s3.py demo "$BUCKET"
}

status() {
  radi || { echo "Garage ne radi"; return 0; }
  g status; g bucket info "$BUCKET" | grep -iE 'bucket|size|objects' || true
}

dolje() {
  if radi; then kill "$(cat "$DIR/pid")" && echo "Garage ugašen"; fi
  rm -f "$DIR/pid"
}

case "${1:-}" in
  up) gore ;;
  test) test_ ;;
  status) status ;;
  down) dolje ;;
  *) echo "Upotreba: $0 up | test | status | down"; exit 1 ;;
esac
