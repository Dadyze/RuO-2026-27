#!/usr/bin/env bash
# s5: mreža laba za DNS, e-poštu i SFTP. Svaki server je jedan network namespace, a svi su na
# zajedničkom "switchu" (bridge u namespace-u ruo5-sw), pa mreža računara ostaje netaknuta.
#
#   računar (admin) 10.50.0.1 --+
#   ruo5-ns1   10.50.0.53  ------+   DNS primarni  (BIND, s5/p1)
#   ruo5-ns2   10.50.0.54  ------+-- [ruo5-sw: br0]  DNS sekundarni (BIND, s5/p1)
#   ruo5-mail  10.50.0.25  ------+   Postfix, Dovecot, OpenDKIM (s5/p3)
#   ruo5-sftp  10.50.0.22  ------+   OpenSSH, samo SFTP (s5/p4)
#   ruo5-van   10.50.0.66  ------+   "vanjski" računar: služi za negativne testove
#
#   ./lab.sh up | status | down        DRY=1 ./lab.sh up  samo ispisuje naredbe (ne mijenja sistem)
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

DRY="${DRY:-0}"
CVOROVI="ns1:53 ns2:54 mail:25 sftp:22 van:66"   # ime:zadnji oktet adrese (10.50.0.<oktet>)

run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }

gore() {
  if [ "$DRY" != 1 ] && ip netns list | grep -qw ruo5-sw; then echo "lab već postoji (./lab.sh down ga briše)"; return 0; fi
  [ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 up"; exit 1; }
  [ "$DRY" = 1 ] || ! ip link show h5 >/dev/null 2>&1 || { echo "+ ip link del h5   # zaostatak"; ip link del h5; }

  # 1. switch: bridge u vlastitom namespace-u (bridge na računaru bi mogao filtrirati Docker/ufw)
  run ip netns add ruo5-sw
  run ip -n ruo5-sw link add br0 type bridge
  run ip -n ruo5-sw link set br0 up
  run ip -n ruo5-sw link set lo up

  # 2. računar je na istoj mreži (10.50.0.1): odavde rade dig, terraform, swaks i sftp
  run ip link add h5 type veth peer name p-host netns ruo5-sw
  run ip -n ruo5-sw link set p-host master br0
  run ip -n ruo5-sw link set p-host up
  run ip addr add 10.50.0.1/24 dev h5
  run ip link set h5 up

  # 3. serveri: namespace + veth prema switchu; resolver svakog servera je naš DNS (10.50.0.53)
  for c in $CVOROVI; do
    ime="${c%%:*}"; n="${c##*:}"
    run ip netns add "ruo5-$ime"
    run ip link add "p-$ime" netns ruo5-sw type veth peer name eth0 netns "ruo5-$ime"
    run ip -n ruo5-sw link set "p-$ime" master br0
    run ip -n ruo5-sw link set "p-$ime" up
    run ip -n "ruo5-$ime" addr add "10.50.0.$n/24" dev eth0
    run ip -n "ruo5-$ime" link set lo up
    run ip -n "ruo5-$ime" link set eth0 up
    run ip -n "ruo5-$ime" route add default via 10.50.0.1
    # ip netns exec montira /etc/netns/<ns>/<datoteka> preko /etc/<datoteka>: svaki server vidi svoj resolv.conf
    run mkdir -p "/etc/netns/ruo5-$ime"
    if [ "$DRY" = 1 ]; then echo "+ echo 'nameserver 10.50.0.53' > /etc/netns/ruo5-$ime/resolv.conf"
    else printf 'nameserver 10.50.0.53\nsearch ruo.lab\n' > "/etc/netns/ruo5-$ime/resolv.conf"; fi
  done
}

stanje() {
  ip -br -4 addr show h5 2>/dev/null || { echo "lab ne radi (sudo ./lab.sh up)"; return 0; }
  for c in $CVOROVI; do
    ns="ruo5-${c%%:*}"
    printf '  %-10s %-16s procesi: %s\n' "$ns" "$(ip -n "$ns" -br -4 addr show eth0 | awk '{print $3}')" \
      "$(ip netns pids "$ns" 2>/dev/null | xargs -r ps -o comm= -p 2>/dev/null | sort -u | tr '\n' ' ')"
  done
}

dolje() {
  for c in $CVOROVI sw:0; do
    ns="ruo5-${c%%:*}"
    # brisanje namespace-a ne zaustavlja procese u njemu, pa se prvo gase oni
    pids="$(ip netns pids "$ns" 2>/dev/null || true)"
    [ -z "$pids" ] || { kill $pids 2>/dev/null || true; sleep 1; kill -9 $pids 2>/dev/null || true; }
    ip netns del "$ns" 2>/dev/null && echo "obrisan $ns" || true
    rm -rf "/etc/netns/$ns"
  done
  ip link del h5 2>/dev/null || true
}

case "${1:-}" in
  up) gore ;;
  status) stanje ;;
  down) dolje ;;
  *) echo "Upotreba: [DRY=1] $0 up | status | down"; exit 1 ;;
esac
