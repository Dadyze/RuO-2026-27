#!/usr/bin/env bash
# s4/p1: "VPC u malom" od Linux network namespace-ova (kontejneri iz sedmice 1 koriste isti mehanizam).
#
#   internet (host) --- r-up --- [ruo-rtr] --- r-web --- ruo-web  10.40.1.0/24
#                                   |--------- r-app --- ruo-app  10.40.2.0/24
#                                   '--------- r-db  --- ruo-db   10.40.3.0/24
#
#   ./lab.sh up | status | down        DRY=1 ./lab.sh up  samo ispisuje naredbe (ne mijenja sistem)
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

DRY="${DRY:-0}"
SEGMENTI="web:1 app:2 db:3"          # ime:redni broj podmreže (10.40.<broj>.0/24)

run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }
rtr() { run ip netns exec ruo-rtr "$@"; }

gore() {
  if [ "$DRY" != 1 ] && ip netns list | grep -qw ruo-rtr; then echo "lab već postoji (./lab.sh down ga briše)"; return 0; fi

  # 0. zaostatak prethodnog pokretanja (namespace je obrisan, ali ga drži neki proces): ukloni host stranu veth para
  [ "$DRY" = 1 ] || ! ip link show h-up >/dev/null 2>&1 || { echo "+ ip link del h-up   # zaostatak"; ip link del h-up; }

  # 1. ruter i uplink prema "internetu" (host)
  run ip netns add ruo-rtr
  run ip link add h-up type veth peer name r-up netns ruo-rtr
  run ip addr add 10.40.0.1/30 dev h-up
  run ip link set h-up up
  run ip -n ruo-rtr addr add 10.40.0.2/30 dev r-up
  run ip -n ruo-rtr link set lo up
  run ip -n ruo-rtr link set r-up up
  run ip route add 10.40.0.0/16 via 10.40.0.2          # povratni put do segmenata
  rtr sysctl -qw net.ipv4.ip_forward=1                 # ruter prosljeđuje pakete
  run ip -n ruo-rtr route add default via 10.40.0.1

  # 2. segmenti: namespace + veth par prema ruteru + zadani put preko rutera
  for s in $SEGMENTI; do
    ime="${s%%:*}"; n="${s##*:}"
    run ip netns add "ruo-$ime"
    run ip link add "r-$ime" netns ruo-rtr type veth peer name eth0 netns "ruo-$ime"
    run ip -n ruo-rtr addr add "10.40.$n.1/24" dev "r-$ime"
    run ip -n ruo-rtr link set "r-$ime" up
    run ip -n "ruo-$ime" addr add "10.40.$n.2/24" dev eth0
    run ip -n "ruo-$ime" link set lo up
    run ip -n "ruo-$ime" link set eth0 up
    run ip -n "ruo-$ime" route add default via "10.40.$n.1"
  done
}

stanje() {
  for ns in ruo-rtr ruo-web ruo-app ruo-db; do
    printf '\n== %s\n' "$ns"; ip -n "$ns" -br -4 addr | grep -v '^lo '; ip -n "$ns" route
  done
}

dolje() {
  for ns in ruo-web ruo-app ruo-db ruo-rtr; do ip netns del "$ns" 2>/dev/null && echo "obrisan $ns" || true; done
  ip link del h-up 2>/dev/null || true                  # veth par (h-up) obično nestane s ruterom, ali ne ako ga nešto drži
  ip route del 10.40.0.0/16 2>/dev/null || true
}

case "${1:-}" in
  up) gore ;;
  status) stanje ;;
  down) dolje ;;
  *) echo "Upotreba: [DRY=1] $0 up | status | down"; exit 1 ;;
esac
