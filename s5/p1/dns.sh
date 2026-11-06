#!/usr/bin/env bash
# s5/p1: autoritativni DNS (BIND) kao kod: primarni ruo5-ns1 i sekundarni ruo5-ns2.
#
#   ./dns.sh provjera     named-checkconf i named-checkzone nad kopijom u privremenom direktoriju (bez root-a)
#   ./dns.sh up           pokreće oba servera u labu (root; lab: sudo ../lab.sh up)
#   ./dns.sh upiti        dig upiti: zapisi, PTR, SRV, AXFR, rekurzija
#   ./dns.sh serial       demonstracija: izmjena zone bez povećanja seriala, pa s povećanjem
#   ./dns.sh kljuc IME    ispisuje TSIG tajnu (ruo-tf, ruo-dkim) za klijente: Terraform, nsupdate
#   ./dns.sh down         gasi servere i briše radne direktorije
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
cd "$(dirname "$0")"

RUN=/var/lib/bind/ruo5             # AppArmor profil BIND-a dozvoljava pisanje samo ispod /var/lib/bind
KLJ=/var/lib/ruo5/kljucevi         # kopije TSIG ključeva za klijente (samo root)

korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
kmd() { echo "\$ $*"; "$@" || true; }
rndc1() { ip netns exec ruo5-ns1 rndc -k "$RUN/ns1/rndc.key" -s 127.0.0.1 "$@"; }
rndc2() { ip netns exec ruo5-ns2 rndc -k "$RUN/ns2/rndc.key" -s 127.0.0.1 "$@"; }

# sastavi radni direktorij servera: konfiguracija i zone iz repozitorija + generisani ključevi
sastavi() { # dir uloga(primarni|sekundarni) keys.conf
  local d="$1"
  mkdir -p "$d/zone" "$d/dyn" "$d/sec"
  cp "named-$2.conf" "$d/named.conf"
  if [ "$2" = primarni ]; then
    cp zone/db.ruo.lab zone/db.10.50.0 "$d/zone/"
    cp zone/db.oblak.ruo.lab zone/db._domainkey.ruo.lab "$d/dyn/"
  fi
  cp "$3" "$d/keys.conf"
  awk '/^key "rndc-ruo"/,/^};/' "$3" > "$d/rndc.key"
}

kljucevi() { # izlazna datoteka: TSIG ključevi (HMAC-SHA256); tajna je nasumična, pa nikad nije u Gitu
  { tsig-keygen -a hmac-sha256 rndc-ruo; tsig-keygen -a hmac-sha256 ruo-tf; tsig-keygen -a hmac-sha256 ruo-dkim; } > "$1"
}

provjera() {
  local t; t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  kljucevi "$t/keys.conf"
  sastavi "$t/ns1" primarni "$t/keys.conf"; sastavi "$t/ns2" sekundarni "$t/keys.conf"
  korak "named-checkconf -z: sintaksa konfiguracije i učitavanje svih zona primarnog"
  (cd "$t/ns1" && named-checkconf -z named.conf)
  korak "named-checkconf: sekundarni"
  (cd "$t/ns2" && named-checkconf named.conf && echo "named-sekundarni.conf je ispravan")
  korak "named-checkzone: zona po zona (serial, NS, glue, CNAME)"
  for z in "ruo.lab zone/db.ruo.lab" "0.50.10.in-addr.arpa zone/db.10.50.0"; do
    set -- $z; named-checkzone "$1" "$2"
  done
}

gore() {
  [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 up"; exit 1; }
  ip netns list | grep -qw ruo5-ns1 || { echo "Lab ne radi: sudo s5/lab.sh up (ili make s5-p1-up)"; exit 1; }
  if [ -f "$RUN/ns1/named.pid" ] && ip netns pids ruo5-ns1 | grep -qx "$(cat "$RUN/ns1/named.pid")"; then
    echo "DNS već radi (./dns.sh down ga gasi)"; return 0
  fi
  rm -rf "$RUN"; mkdir -p "$RUN" "$KLJ"; chmod 700 "$KLJ"
  kljucevi "$KLJ/keys.conf"
  for k in ruo-tf ruo-dkim; do awk "/^key \"$k\"/,/^};/" "$KLJ/keys.conf" > "$KLJ/$k.key"; done
  sastavi "$RUN/ns1" primarni "$KLJ/keys.conf"; sastavi "$RUN/ns2" sekundarni "$KLJ/keys.conf"
  chown -R bind:bind "$RUN"; chmod 750 "$RUN"
  # named -f: u prvom planu (setsid ga odvaja od terminala), -u bind: bez root prava nakon otvaranja porta 53
  for s in ns1 ns2; do
    ip netns exec "ruo5-$s" setsid -f bash -c "cd $RUN/$s && exec named -f -u bind -c named.conf" >>"$RUN/$s/stderr.log" 2>&1 </dev/null
  done
  for _ in $(seq 20); do dig +short +time=1 +tries=1 @10.50.0.54 ruo.lab SOA 2>/dev/null | grep -q . && break; sleep 0.5; done
  echo "ns1 (primarni)   10.50.0.53: $(rndc1 status | grep -E '^(version|server is up)' | tr '\n' ' ')"
  echo "ns2 (sekundarni) 10.50.0.54: zone preuzete: $(ls "$RUN/ns2/sec" | tr '\n' ' ')"
}

upiti() {
  local D="dig +noall +answer +nottlid @10.50.0.53"
  korak "1. Puni odgovor jednog upita: zaglavlje (flags: aa = autoritativni odgovor) i sekcije"
  kmd dig +nocmd +nostats +noquestion +noedns @10.50.0.53 mail.ruo.lab A
  korak "2. Zapisi zone (kratko): A, CNAME, MX, SRV, CAA"
  kmd $D mail.ruo.lab A
  kmd $D imap.ruo.lab A
  kmd $D ruo.lab MX
  kmd $D _submission._tcp.ruo.lab SRV
  kmd $D ruo.lab CAA
  korak "3. E-pošta: SPF i DMARC su TXT zapisi"
  kmd $D ruo.lab TXT
  kmd $D _dmarc.ruo.lab TXT
  korak "4. Reverzni upit (PTR): adresa -> ime"
  kmd dig +short @10.50.0.53 -x 10.50.0.25
  korak "5. Isti odgovor daje i sekundarni (isti serial u SOA)"
  kmd dig +short @10.50.0.53 ruo.lab SOA
  kmd dig +short @10.50.0.54 ruo.lab SOA
  korak "6. Prijenos zone (AXFR): sekundarnom dozvoljen, svima ostalima odbijen"
  echo "[ruo5-ns2]\$ dig @10.50.0.53 ruo.lab AXFR | grep -c IN"
  ip netns exec ruo5-ns2 dig +noall +answer @10.50.0.53 ruo.lab AXFR | grep -c IN || true
  echo "[ruo5-van]\$ dig @10.50.0.53 ruo.lab AXFR"
  ip netns exec ruo5-van dig +noall +answer @10.50.0.53 ruo.lab AXFR || true
  korak "7. Nepostojeće ime (NXDOMAIN) i tuđa domena (REFUSED: server nije rekurzivni)"
  for q in nema.ruo.lab example.com; do
    echo "\$ dig @10.50.0.53 $q A   ->  $(dig @10.50.0.53 "$q" A | grep -o 'status: [A-Z]*')"
  done
}

serial() {
  [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 serial"; exit 1; }
  local z="$RUN/ns1/zone/db.ruo.lab" s ime
  s="$(awk '/; serial/{print $1}' "$z")"
  ime="test$(date +%H%M%S)"              # novo ime pri svakom pokretanju, pa se demonstracija može ponavljati
  korak "1. Dodajemo zapis $ime.ruo.lab u radnu kopiju zone, ali serial OSTAJE $s"
  echo "$ime    IN A      10.50.0.99" >> "$z"
  echo "\$ rndc reload ruo.lab"; rndc1 reload ruo.lab
  sleep 2
  echo "primarni:   $(dig +short @10.50.0.53 $ime.ruo.lab A)   (serial $(dig +short @10.50.0.53 ruo.lab SOA | awk '{print $3}'))"
  echo "sekundarni: $(dig +short @10.50.0.54 $ime.ruo.lab A)   (serial $(dig +short @10.50.0.54 ruo.lab SOA | awk '{print $3}'), prazno = ne zna za zapis)"
  korak "2. Povećavamo serial ($s -> $((s + 1))): primarni šalje NOTIFY, sekundarni povlači promjenu"
  sed -i "s/$s ; serial/$((s + 1)) ; serial/" "$z"
  echo "\$ rndc reload ruo.lab"; rndc1 reload ruo.lab
  for _ in $(seq 10); do [ -n "$(dig +short @10.50.0.54 $ime.ruo.lab A)" ] && break; sleep 0.5; done
  echo "primarni:   $(dig +short @10.50.0.53 $ime.ruo.lab A)   (serial $(dig +short @10.50.0.53 ruo.lab SOA | awk '{print $3}'))"
  echo "sekundarni: $(dig +short @10.50.0.54 $ime.ruo.lab A)   (serial $(dig +short @10.50.0.54 ruo.lab SOA | awk '{print $3}'))"
  korak "3. Dnevnik sekundarnog: NOTIFY i prijenos (IXFR/AXFR)"
  grep -E "notify from|transfer of 'ruo.lab" "$RUN/ns2/named.log" | tail -3 | cut -c25-
  echo
  echo "Napomena: izmjena je u radnoj kopiji. Trajno se mijenja s5/p1/zone/db.ruo.lab u Gitu (sljedeći up je vraća na stanje iz Gita)."
}

kljuc() { awk -F'"' '/secret/{print $2}' "$KLJ/${1:?ime ključa}.key"; }

dolje() {
  local p
  for s in ns1 ns2; do
    p="$(cat "$RUN/$s/named.pid" 2>/dev/null || true)"
    [ -n "$p" ] && kill "$p" 2>/dev/null || continue
    for _ in $(seq 20); do kill -0 "$p" 2>/dev/null || break; sleep 0.25; done   # čeka da named zapiše i izađe
    echo "zaustavljen named ($s)"
  done
  rm -rf "$RUN" "$KLJ"
}

case "${1:-}" in
  provjera) provjera ;;
  up) gore ;;
  upiti) upiti ;;
  serial) serial ;;
  kljuc) kljuc "${2:-}" ;;
  down) dolje ;;
  *) echo "Upotreba: $0 provjera | up | upiti | serial | kljuc IME | down"; exit 1 ;;
esac
