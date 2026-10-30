#!/usr/bin/env bash
# s4/p3: Linux bridge kao L2 preklopnik s VLAN-ovima (802.1Q), u namespace-ovima (root).
#
#   ruo-h10a --(VLAN 10)--+
#   ruo-h10b --(VLAN 10)--+-- [ruo-sw: br0, vlan_filtering]
#   ruo-h20  --(VLAN 20)--+
#
#   ./vlan.sh up | test | down        DRY=1 ./vlan.sh up  samo ispisuje naredbe
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
DRY="${DRY:-0}"
run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }

port() { # ime  vlan  ip     pristupni port: okviri bez oznake ulaze u zadani VLAN
  run ip netns add "ruo-$1"
  run ip link add "p-$1" netns ruo-sw type veth peer name eth0 netns "ruo-$1"
  run ip -n ruo-sw link set "p-$1" master br0
  run ip -n ruo-sw link set "p-$1" up
  run bridge -n ruo-sw vlan add dev "p-$1" vid "$2" pvid untagged   # ulazni okvir bez oznake -> VLAN $2
  run bridge -n ruo-sw vlan del dev "p-$1" vid 1                    # ukloni zadani VLAN 1 s porta
  run ip -n "ruo-$1" addr add "$3" dev eth0
  run ip -n "ruo-$1" link set lo up
  run ip -n "ruo-$1" link set eth0 up
}

gore() {
  run ip netns add ruo-sw
  run ip -n ruo-sw link add br0 type bridge vlan_filtering 1   # bez vlan_filtering bridge ignoriše VLAN-ove
  run ip -n ruo-sw link set br0 up
  port h10a 10 10.50.10.11/24
  port h10b 10 10.50.10.12/24
  port h20  20 10.50.10.21/24     # ista podmreža, ali drugi VLAN: izolirana je na sloju 2
}

dolje() { for ns in ruo-h10a ruo-h10b ruo-h20 ruo-sw; do ip netns del "$ns" 2>/dev/null && echo "obrisan $ns" || true; done; }

proba() { # izvor odredište-ip očekivano
  if ip netns exec "ruo-$1" timeout 2 bash -c "exec 3<>/dev/tcp/$2/9000" 2>/dev/null; then rez=dozvoljeno; else rez=blokirano; fi
  [ "$rez" = "$3" ] && oz=ok || oz=RAZLIKA
  printf '  %-5s -> %-11s %-11s (očekivano: %-10s) %s\n' "$1" "$2" "$rez" "$3" "$oz"
}
test_() {
  local pids=() kod='import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind((sys.argv[1],9000)); s.listen(8)
while True: s.accept()[0].close()'
  ip netns exec ruo-h10b python3 -c "$kod" 10.50.10.12 & pids+=($!)
  ip netns exec ruo-h20  python3 -c "$kod" 10.50.10.21 & pids+=($!)
  sleep 1
  proba h10a 10.50.10.12 dozvoljeno    # isti VLAN
  proba h10a 10.50.10.21 blokirano     # drugi VLAN, iako je adresa u istoj podmreži
  proba h20  10.50.10.12 blokirano
  kill "${pids[@]}" 2>/dev/null || true
}

case "${1:-}" in up) gore ;; test) test_ ;; down) dolje ;; *) echo "Upotreba: [DRY=1] $0 up | test | down"; exit 1 ;; esac
