#!/usr/bin/env bash
# s4/p3: šta VPN klijent smije. Zahtijeva s4/p1 (lab), s4/p2 (vatrozid) i s4/p3/wg.sh up (root).
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
PIDS=()
slusaj() { ip netns exec "$1" python3 -c 'import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind((sys.argv[1],int(sys.argv[2]))); s.listen(16)
while True: s.accept()[0].close()' "$2" "$3" & PIDS+=($!); }
trap 'kill "${PIDS[@]}" 2>/dev/null' EXIT
slusaj ruo-app 10.40.2.2 8080; slusaj ruo-web 10.40.1.2 80; slusaj ruo-db 10.40.3.2 5432
sleep 1
proba() { # odredište-ip port očekivano
  if ip netns exec ruo-klijent timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then rez=dozvoljeno; else rez=blokirano; fi
  [ "$rez" = "$3" ] && oz=ok || oz=RAZLIKA
  printf '  klijent -> %-10s :%-5s  %-11s (očekivano: %-10s) %s\n' "$1" "$2" "$rez" "$3" "$oz"
}
proba 10.40.2.2 8080 dozvoljeno   # app kroz tunel
proba 10.40.3.2 5432 blokirano    # db: nema rute u tunelu (AllowedIPs) ni pravila u vatrozidu
proba 10.40.1.2 80   blokirano    # web: nije u AllowedIPs, pa promet ne ide kroz tunel
echo; echo "  promet kroz tunel (ruter): $(ip netns exec ruo-rtr wg show wg-rtr transfer | awk '{printf "%s B primljeno, %s B poslano", $2, $3}')"
