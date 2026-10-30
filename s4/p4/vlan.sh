#!/usr/bin/env bash
# s4/p4: Linux bridge kao L2 preklopnik s VLAN-ovima (802.1Q), u namespace-ovima (root).
#
#   ruo-h10a --(access VLAN 10)--+
#   ruo-h10b --(access VLAN 10)--+-- [ruo-sw: br0, vlan_filtering] -- trunk (10,20) -- ruo-trk
#   ruo-h20  --(access VLAN 20)--+                                       (host s oznakama: eth0.10, eth0.20)
#
#   ./vlan.sh up | status | down | test        DRY=1 ./vlan.sh up  samo ispisuje naredbe
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
DRY="${DRY:-0}"
run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }
sw()  { run ip -n ruo-sw "$@"; }

port() { # ime  vlan  ip      pristupni port: pakete bez oznake sklopka sama stavlja u VLAN
  run ip netns add "ruo-$1"
  run ip link add "p-$1" netns ruo-sw type veth peer name eth0 netns "ruo-$1"
  sw link set "p-$1" master br0
  sw link set "p-$1" up
  run bridge -n ruo-sw vlan add dev "p-$1" vid "$2" pvid untagged   # ulazni okvir bez oznake -> VLAN $2
  run bridge -n ruo-sw vlan del dev "p-$1" vid 1                    # ukloni zadani VLAN 1 s porta
  run ip -n "ruo-$1" addr add "$3" dev eth0
  run ip -n "ruo-$1" link set lo up
  run ip -n "ruo-$1" link set eth0 up
}

gore() {
  run ip netns add ruo-sw
  sw link add br0 type bridge vlan_filtering 1       # bez vlan_filtering bridge ignoriše VLAN oznake
  sw link set br0 up
  port h10a 10 10.50.10.11/24
  port h10b 10 10.50.10.12/24
  port h20  20 10.50.20.21/24

  # trunk: okviri nose oznaku (tagged); host razdvaja VLAN-ove podinterfejsima eth0.10 i eth0.20
  run ip netns add ruo-trk
  run ip link add p-trk netns ruo-sw type veth peer name eth0 netns ruo-trk
  sw link set p-trk master br0
  sw link set p-trk up
  run bridge -n ruo-sw vlan add dev p-trk vid 10
  run bridge -n ruo-sw vlan add dev p-trk vid 20
  run bridge -n ruo-sw vlan del dev p-trk vid 1
  run ip -n ruo-trk link set lo up
  run ip -n ruo-trk link set eth0 up
  run ip -n ruo-trk link add link eth0 name eth0.10 type vlan id 10
  run ip -n ruo-trk link add link eth0 name eth0.20 type vlan id 20
  run ip -n ruo-trk addr add 10.50.10.1/24 dev eth0.10
  run ip -n ruo-trk addr add 10.50.20.1/24 dev eth0.20
  run ip -n ruo-trk link set eth0.10 up
  run ip -n ruo-trk link set eth0.20 up
}

stanje() { printf '\n== VLAN-ovi na portovima sklopke\n'; bridge -n ruo-sw vlan show; }

dolje() { for ns in ruo-h10a ruo-h10b ruo-h20 ruo-trk ruo-sw; do ip netns del "$ns" 2>/dev/null && echo "obrisan $ns" || true; done; }

proba() { # izvor ip očekivano
  if ip netns exec "ruo-$1" timeout 2 bash -c "exec 3<>/dev/tcp/$2/9000" 2>/dev/null; then rez=dozvoljeno; else rez=blokirano; fi
  [ "$rez" = "$3" ] && oz=ok || oz=RAZLIKA
  printf '  %-6s -> %-11s %-11s (očekivano: %-10s) %s\n' "$1" "$2" "$rez" "$3" "$oz"
}
test_() {
  local pids=() kod='import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind((sys.argv[1],9000)); s.listen(8)
while True: s.accept()[0].close()'
  ip netns exec ruo-h10b python3 -c "$kod" 10.50.10.12 & pids+=($!)
  ip netns exec ruo-h20  python3 -c "$kod" 10.50.20.21 & pids+=($!)
  ip netns exec ruo-trk  python3 -c "$kod" 10.50.10.1  & pids+=($!)
  ip netns exec ruo-trk  python3 -c "$kod" 10.50.20.1  & pids+=($!)
  sleep 1
  proba h10a 10.50.10.12 dozvoljeno    # isti VLAN
  proba h10a 10.50.20.21 blokirano     # drugi VLAN (druga L2 domena, nema rute)
  proba h20  10.50.10.12 blokirano
  proba h10a 10.50.10.1  dozvoljeno    # trunk host je u VLAN-u 10
  proba h20  10.50.20.1  dozvoljeno    # trunk host je i u VLAN-u 20 (oznaka 20 na istoj žici)
  proba h10a 10.50.20.1  blokirano     # slušalac postoji, ali je u drugom VLAN-u
  kill "${pids[@]}" 2>/dev/null || true
}

case "${1:-}" in up) gore ;; status) stanje ;; down) dolje ;; test) test_ ;; *) echo "Upotreba: [DRY=1] $0 up | status | down | test"; exit 1 ;; esac
