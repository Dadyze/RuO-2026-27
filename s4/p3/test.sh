#!/usr/bin/env bash
# s4/p3: matrica povezivosti. Na svakom odredištu radi TCP slušalac, pa se vidi da li je veza
# dozvoljena ili blokirana; "očekivano" je politika iz firewall.nft. Zahtijeva lab iz s4/p2 (root).
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

PIDS=()
slusaj() { # ns ip port: prihvata veze i odmah ih zatvara
  local kod='import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind((sys.argv[1],int(sys.argv[2]))); s.listen(16)
while True: s.accept()[0].close()'
  if [ "$1" = host ]; then python3 -c "$kod" "$2" "$3" &
  else ip netns exec "$1" python3 -c "$kod" "$2" "$3" &
  fi
  PIDS+=($!)
}
trap 'kill "${PIDS[@]}" 2>/dev/null' EXIT

slusaj ruo-web 10.40.1.2 80
slusaj ruo-app 10.40.2.2 8080;  slusaj ruo-app 10.40.2.2 22
slusaj ruo-db  10.40.3.2 5432;  slusaj ruo-db  10.40.3.2 22
slusaj host    10.40.0.1 9000
sleep 1

proba() { # izvor  odredište-ip  port  očekivano
  local izv="$1" ip="$2" port="$3" ocek="$4" cmd rez oz
  cmd="exec 3<>/dev/tcp/$ip/$port"
  if [ "$izv" = host ]; then timeout 2 bash -c "$cmd" 2>/dev/null; else ip netns exec "ruo-$izv" timeout 2 bash -c "$cmd" 2>/dev/null; fi \
    && rez=dozvoljeno || rez=blokirano
  [ "$rez" = "$ocek" ] && oz="ok" || oz="RAZLIKA"
  printf '  %-6s -> %-10s :%-5s  %-11s (očekivano: %-10s) %s\n' "$izv" "$ip" "$port" "$rez" "$ocek" "$oz"
}

proba host 10.40.1.2 80   dozvoljeno   # internet -> web
proba host 10.40.2.2 8080 blokirano    # internet -> app
proba host 10.40.3.2 5432 blokirano    # internet -> db
proba web  10.40.2.2 8080 dozvoljeno   # web -> app (aplikacijski port)
proba web  10.40.2.2 22   blokirano    # web -> app (SSH)
proba web  10.40.3.2 5432 blokirano    # web -> db (preskakanje sloja)
proba app  10.40.3.2 5432 dozvoljeno   # app -> db
proba app  10.40.3.2 22   blokirano    # app -> db (SSH)
proba web  10.40.0.1 9000 dozvoljeno   # web -> internet (preko NAT-a)
proba db   10.40.0.1 9000 blokirano    # db -> internet
