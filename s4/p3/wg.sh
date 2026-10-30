#!/usr/bin/env bash
# s4/p3: WireGuard VPN između "kancelarije" (ruo-vpn-klijent) i ruo-rtr. Klijent dobiva pristup samo
# bastion/app segmentu (AllowedIPs), a ključevi se prave lokalno i NE idu u Git.
#
#   ./wg.sh up | status | down        (root; zahtijeva lab iz s4/p1)
#   DRY=1 ./wg.sh up                  samo ispisuje naredbe (ne mijenja sistem, ne traži root)
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

DIR="$(cd "$(dirname "$0")" && pwd)/keys"       # keys/ je u .gitignore
KLIJENT=ruo-klijent
pub() { if [ "$DRY" = 1 ]; then echo "<javni-kljuc-$1>"; else cat "$DIR/$1.pub"; fi; }
DRY="${DRY:-0}"
run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }

# WireGuard sučelje u namespace-u: kernelski modul ako postoji, inače korisnički wireguard-go (npr. WSL2 bez modula).
# Imena sučelja moraju biti različita (wg-rtr, wg-kl): wireguard-go pravi /var/run/wireguard/<ime>.sock,
# a taj direktorij se NE izolira po namespace-u.
wg_sucelje() { # namespace ime
  if [ "$DRY" = 1 ]; then echo "+ ip -n $1 link add $2 type wireguard"; return 0; fi
  if ip -n "$1" link add "$2" type wireguard 2>/dev/null; then echo "+ ip -n $1 link add $2 type wireguard"
  else echo "+ (nema kernelskog modula) ip netns exec $1 wireguard-go $2"; ip netns exec "$1" wireguard-go "$2" >/dev/null 2>&1 </dev/null; fi
}

gore() {
  if [ "$DRY" = 1 ]; then DIR=/nema/keys; else
  ip netns list | grep -qw ruo-rtr || { echo "Prvo: s4/p1/lab.sh up"; exit 1; }
  mkdir -p "$DIR"; umask 077
  [ -f "$DIR/rtr.key" ] || { wg genkey | tee "$DIR/rtr.key" | wg pubkey > "$DIR/rtr.pub"; }
  [ -f "$DIR/klijent.key" ] || { wg genkey | tee "$DIR/klijent.key" | wg pubkey > "$DIR/klijent.pub"; }
  fi

  # "kancelarija" je zaseban namespace, spojen na uplink rutera preko veth para (kao internet)
  [ "$DRY" = 1 ] || ! ip netns list | grep -qw "$KLIJENT" || { echo "već postoji (./wg.sh down)"; return 0; }
  run ip netns add "$KLIJENT"
  run ip link add k-up type veth peer name r-k netns ruo-rtr
  run ip link set k-up netns "$KLIJENT"
  run ip -n "$KLIJENT" addr add 10.40.9.2/30 dev k-up
  run ip -n "$KLIJENT" link set lo up
  run ip -n "$KLIJENT" link set k-up up
  run ip -n ruo-rtr addr add 10.40.9.1/30 dev r-k
  run ip -n ruo-rtr link set r-k up

  # WireGuard sučelje na ruteru: tunelska mreža 10.99.0.0/24, UDP 51820
  wg_sucelje ruo-rtr wg-rtr
  run ip netns exec ruo-rtr wg set wg-rtr listen-port 51820 private-key "$DIR/rtr.key" \
        peer "$(pub klijent)" allowed-ips 10.99.0.2/32
  run ip -n ruo-rtr addr add 10.99.0.1/24 dev wg-rtr
  run ip -n ruo-rtr link set wg-rtr up

  # klijent: sve za 10.40.2.0/24 (app) ide kroz tunel, ne cijeli internet (split tunnel)
  wg_sucelje "$KLIJENT" wg-kl
  run ip netns exec "$KLIJENT" wg set wg-kl private-key "$DIR/klijent.key" \
        peer "$(pub rtr)" endpoint 10.40.9.1:51820 allowed-ips 10.99.0.1/32,10.40.2.0/24 persistent-keepalive 5
  run ip -n "$KLIJENT" addr add 10.99.0.2/24 dev wg-kl
  run ip -n "$KLIJENT" link set wg-kl up
  run ip -n "$KLIJENT" route add 10.40.2.0/24 dev wg-kl
}

stanje() { printf '\n== ruo-rtr\n'; ip netns exec ruo-rtr wg show wg-rtr; printf '\n== %s\n' "$KLIJENT"; ip netns exec "$KLIJENT" wg show wg-kl; }
dolje()  { pkill -x wireguard-go 2>/dev/null || true; ip netns del "$KLIJENT" 2>/dev/null && echo "obrisan $KLIJENT" || true; ip -n ruo-rtr link del wg-rtr 2>/dev/null || true; ip -n ruo-rtr link del r-k 2>/dev/null || true; }

case "${1:-}" in up) gore ;; status) stanje ;; down) dolje ;; *) echo "Upotreba: $0 up | status | down"; exit 1 ;; esac
