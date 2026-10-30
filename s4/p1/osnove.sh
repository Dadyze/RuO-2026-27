#!/usr/bin/env bash
# s4/p1: osnovni mrežni zadaci naredbom ip: pregled, dodavanje, mijenjanje i brisanje adresa, sučelja i ruta.
# Sve se radi u dva izolirana namespace-a (ruo-n1, ruo-n2) spojena veth kablom, pa mreža računara ostaje netaknuta.
#
#   ./osnove.sh pregled            samo čita stanje mreže računara (ne traži root)
#   ./osnove.sh vjezba             cijela vježba korak po korak (root)    PAUZA=1: čeka Enter nakon svakog koraka
#   ./osnove.sh down               briše namespace-ove
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
PAUZA="${PAUZA:-0}"

korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
# kmd [ns] naredba...: ispiše naredbu i izvrši je (u namespace-u ako je prvi argument ruo-n1 ili ruo-n2)
kmd() {
  if [[ "$1" == ruo-n* ]]; then local ns="$1"; shift; echo "[$ns]\$ $*"; ip netns exec "$ns" "$@"
  else echo "\$ $*"; "$@"; fi
  return 0
}
pauza() { [ "$PAUZA" = 1 ] && read -r -p "   (Enter za nastavak) " _ || true; }
ping1() { local ns="$1" cilj="$2"; if ip netns exec "$ns" ping -c1 -W1 "$cilj" >/dev/null 2>&1; then echo "[$ns] ping $cilj: ODGOVARA"; else echo "[$ns] ping $cilj: NE ODGOVARA"; fi; }

pregled() {
  korak "1. Pregled sučelja (ip -br link): ime, stanje, MAC"
  kmd ip -br link
  korak "2. Pregled adresa (ip -br addr): ko ima koju IP adresu"
  kmd ip -br addr
  korak "3. Tabela usmjeravanja (ip route) i put do određene adrese (ip route get)"
  kmd ip route
  kmd ip route get 1.1.1.1
}

vjezba() {
  [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 vjezba"; exit 1; }
  down >/dev/null 2>&1
  ip netns add ruo-n1; ip netns add ruo-n2
  ip link add eth0 netns ruo-n1 type veth peer name eth0 netns ruo-n2

  korak "1. Početno stanje: sučelje postoji, ali je isključeno i nema adresu"
  kmd ruo-n1 ip -br link; kmd ruo-n1 ip -br addr; pauza

  korak "2. Uključivanje sučelja (up): bez adrese ono još ne može slati IP promet"
  kmd ruo-n1 ip link set lo up; kmd ruo-n1 ip link set eth0 up
  kmd ruo-n2 ip link set lo up; kmd ruo-n2 ip link set eth0 up
  kmd ruo-n1 ip -br addr; pauza

  korak "3. Dodavanje adrese (ip addr add): oblik adresa/prefiks; jezgra sama dodaje rutu za podmrežu"
  kmd ruo-n1 ip addr add 10.60.0.1/24 dev eth0
  kmd ruo-n2 ip addr add 10.60.0.2/24 dev eth0
  kmd ruo-n1 ip -br addr; kmd ruo-n1 ip route
  ping1 ruo-n1 10.60.0.2; pauza

  korak "4. Druga adresa na istom sučelju (dozvoljeno: sučelje može imati više adresa)"
  kmd ruo-n1 ip addr add 10.60.0.11/24 dev eth0
  kmd ruo-n1 ip -br addr; pauza

  korak "5. Mijenjanje adrese: IP se ne 'uređuje', stara se briše a nova dodaje (n2: .2 -> .22)"
  kmd ruo-n2 ip addr del 10.60.0.2/24 dev eth0
  kmd ruo-n2 ip addr add 10.60.0.22/24 dev eth0
  ping1 ruo-n1 10.60.0.2; ping1 ruo-n1 10.60.0.22; pauza

  korak "6. Mijenjanje svojstava sučelja: MTU (najveća veličina paketa) i isključivanje/uključivanje"
  kmd ruo-n1 ip link set eth0 mtu 1400
  kmd ruo-n1 ip link show eth0
  kmd ruo-n1 ip link set eth0 down; ping1 ruo-n1 10.60.0.22
  kmd ruo-n1 ip link set eth0 up;   ping1 ruo-n1 10.60.0.22; pauza

  korak "7. Rute: n2 ima još jednu mrežu (10.70.0.1 na lo); n1 do nje nema puta dok se ruta ne doda"
  kmd ruo-n2 ip addr add 10.70.0.1/24 dev lo
  ping1 ruo-n1 10.70.0.1
  kmd ruo-n1 ip route add 10.70.0.0/24 via 10.60.0.22
  kmd ruo-n1 ip route get 10.70.0.1
  ping1 ruo-n1 10.70.0.1
  kmd ruo-n1 ip route del 10.70.0.0/24
  ping1 ruo-n1 10.70.0.1; pauza

  korak "8. Brisanje adrese (ip addr del) i brisanje svih adresa sa sučelja (ip addr flush)"
  kmd ruo-n1 ip addr del 10.60.0.11/24 dev eth0
  kmd ruo-n1 ip -br addr
  kmd ruo-n1 ip addr flush dev eth0
  kmd ruo-n1 ip -br addr; kmd ruo-n1 ip route
  echo "(prazna tabela usmjeravanja: rute iz adrese nestaju zajedno s njom)"; ping1 ruo-n1 10.60.0.22; pauza

  korak "9. Statistika sučelja (ip -s link): brojači paketa i grešaka, prvo mjesto za dijagnostiku"
  kmd ruo-n2 ip -s link show eth0
  echo; echo "Promjene su privremene: nestaju s namespace-om (a na pravoj mašini s restartom). Trajna konfiguracija: netplan (s4/p1/netplan-primjer.yaml)."
}

down() { ip netns del ruo-n1 2>/dev/null && echo "obrisan ruo-n1" || true; ip netns del ruo-n2 2>/dev/null && echo "obrisan ruo-n2" || true; }

case "${1:-}" in pregled) pregled ;; vjezba) vjezba ;; down) down ;; *) echo "Upotreba: $0 pregled | vjezba | down"; exit 1 ;; esac
