#!/usr/bin/env bash
# s5/p3: e-pošta kao kod: Postfix (SMTP), Dovecot (IMAP, LMTP, prijava), OpenDKIM, TLS, SPF/DKIM/DMARC.
#
#   ./mail.sh provjera   postconf, doveconf i opendkim -n nad kopijom konfiguracije (bez root-a, ništa ne pokreće)
#   ./mail.sh up         TLS certifikat, DKIM ključ (objava u DNS), pokretanje servisa u ruo5-mail (root; traži s5-p1-up)
#   ./mail.sh test       slanje, čitanje, TLS, provjera DKIM/SPF/DMARC i negativni slučajevi (root)
#   ./mail.sh down       gasi servise i briše podatke
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
cd "$(dirname "$0")"

ETC=/etc/ruo5/mail                 # konfiguracija u radu (izvor je ovaj direktorij)
VAR=/var/lib/ruo5                  # sandučići, DKIM ključ, CA, logovi
SPOOL=/var/spool/ruo5-postfix      # red čekanja Postfixa
NS="ip netns exec ruo5-mail"
VAN="ip netns exec ruo5-van"       # "vanjski" računar: korisnik na laptopu ili tuđi server
CA="$VAR/ca/ca.crt"

korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
# tvrdi "opis" naredba...: provjera koja ne prekida skriptu; na kraju se broje neuspjele
tvrdi() { local o="$1"; shift; if "$@"; then echo "  ok: $o"; else echo "  NIJE OK: $o"; GRESKE=$((GRESKE + 1)); fi; }
sadrzi() { grep -q -- "$2" <<< "$1"; }
nije() { ! "$@"; }
GRESKE=0

# konfiguracija iz repozitorija u odredište; prefiks omogućava provjeru u privremenom direktoriju
sastavi() { # odredište(etc) prefiks-za-putanje
  local d="$1" p="$2"
  mkdir -p "$d/postfix" "$d/dovecot" "$d/tls"
  for f in postfix/main.cf postfix/master.cf dovecot/dovecot.conf opendkim.conf; do
    sed -e "s#/etc/ruo5/mail#$p/etc/ruo5/mail#g" -e "s#/var/lib/ruo5#$p/var/lib/ruo5#g" "$f" > "$d/$f"
  done
  # iz korisnici.txt: popis sandučića za Postfix i hashirane lozinke za Dovecot
  grep -v '^#' korisnici.txt | awk 'NF==2{print $1, "ok"}' > "$d/postfix/sanducici"
  grep -v '^#' korisnici.txt | while read -r a l; do
    [ -n "$a" ] && echo "$a:$(doveadm pw -s SHA512-CRYPT -p "$l")"
  done > "$d/dovecot/korisnici"
  chmod 640 "$d/dovecot/korisnici"
}

tls() { # dir_ca dir_cert: lab CA i certifikat za mail.ruo.lab (u produkciji ga izdaje ACME CA)
  local c="$1" t="$2"
  if [ ! -f "$c/ca.crt" ]; then
    mkdir -p "$c"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
      -subj "/CN=RuO lab CA" -keyout "$c/ca.key" -out "$c/ca.crt" \
      -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
  fi
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=mail.ruo.lab" \
    -keyout "$t/mail.key" -out "$t/mail.csr" 2>/dev/null
  openssl x509 -req -in "$t/mail.csr" -CA "$c/ca.crt" -CAkey "$c/ca.key" -CAcreateserial -days 30 \
    -extfile <(printf 'subjectAltName=DNS:mail.ruo.lab,DNS:imap.ruo.lab,DNS:smtp.ruo.lab\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nauthorityKeyIdentifier=keyid\n') \
    -out "$t/mail.crt" 2>/dev/null
  rm -f "$t/mail.csr"; chmod 640 "$t/mail.key"
}

provjera() {
  # privremeni direktorij u $HOME, ne u /tmp: OpenDKIM odbija ključ na putanji u koju drugi mogu pisati
  local t; t="$(mktemp -d -p "$HOME" .ruo5-provjera.XXXX)"; trap 'rm -rf "$t"' RETURN
  sastavi "$t/etc/ruo5/mail" "$t"; tls "$t/ca" "$t/etc/ruo5/mail/tls"
  korak "postconf -n: parametri koji se razlikuju od zadanih (nepoznat parametar = upozorenje)"
  postconf -c "$t/etc/ruo5/mail/postfix" -n 2>&1 | sed "s#$t##g"
  korak "postconf -M: servisi iz master.cf"
  postconf -c "$t/etc/ruo5/mail/postfix" -M smtp/inet submission/inet
  korak "doveconf -n: Dovecot konfiguracija se parsira"
  doveconf -c "$t/etc/ruo5/mail/dovecot/dovecot.conf" -n >/dev/null && echo "dovecot.conf je ispravan"
  korak "opendkim -n: OpenDKIM konfiguracija (s privremenim ključem)"
  mkdir -p "$t/var/lib/ruo5/dkim" && opendkim-genkey -b 1024 -d ruo.lab -s ruo2026 -D "$t/var/lib/ruo5/dkim"
  opendkim -n -x "$t/etc/ruo5/mail/opendkim.conf" && echo "opendkim.conf je ispravan"
}

gore() {
  [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 up"; exit 1; }
  dig +short +time=1 +tries=1 @10.50.0.53 ruo.lab SOA | grep -q . || { echo "DNS ne radi: make s5-p1-up"; exit 1; }
  if ip netns pids ruo5-mail | xargs -r ps -o comm= -p | grep -qx master; then echo "mail već radi (./mail.sh down ga gasi)"; return 0; fi

  korak "1. Konfiguracija u $ETC"
  rm -rf "$ETC"; sastavi "$ETC" ""; chgrp dovecot "$ETC/dovecot/korisnici"
  mkdir -p "$VAR/postfix" "$VAR/mail" "$VAR/dkim" /run/ruo5/dovecot "$SPOOL"
  chown postfix "$VAR/postfix"; chown mail:mail "$VAR/mail"
  echo "postfix, dovecot, opendkim + sandučići: $(awk '{printf "%s ", $1}' "$ETC/postfix/sanducici")"

  korak "2. TLS: certifikat za mail.ruo.lab potpisan CA-om laba"
  tls "$VAR/ca" "$ETC/tls"; chgrp -R dovecot "$ETC/tls"
  openssl x509 -in "$ETC/tls/mail.crt" -noout -subject -issuer -ext subjectAltName | sed 's/^/  /'

  korak "3. DKIM: par ključeva; privatni ostaje na serveru, javni se objavljuje u DNS-u"
  [ -f "$VAR/dkim/ruo2026.private" ] || opendkim-genkey -b 2048 -d ruo.lab -s ruo2026 -D "$VAR/dkim"
  chown -R opendkim "$VAR/dkim"; chmod 600 "$VAR/dkim/ruo2026.private"
  # zapis iz ruo2026.txt (više navodnicima odvojenih dijelova, svaki do 255 znakova) šaljemo kao RFC 2136 UPDATE
  local txt; txt="$(tr -d '\n' < "$VAR/dkim/ruo2026.txt" | sed -e 's/.*( *//' -e 's/ *).*//' -e 's/"\s*"/" "/g')"
  nsupdate -k /var/lib/ruo5/kljucevi/ruo-dkim.key <<EOF
server 10.50.0.53
zone _domainkey.ruo.lab
update delete ruo2026._domainkey.ruo.lab. TXT
update add ruo2026._domainkey.ruo.lab. 300 TXT $txt
send
EOF
  echo "\$ dig +short ruo2026._domainkey.ruo.lab TXT"
  sleep 1; dig +short @10.50.0.54 ruo2026._domainkey.ruo.lab TXT | cut -c1-90 | sed 's/$/.../'

  korak "4. Pokretanje u namespace-u ruo5-mail: OpenDKIM, Postfix (pravi red čekanja), pa Dovecot (socketi u njemu)"
  $NS setsid -f opendkim -x "$ETC/opendkim.conf" >>"$VAR/opendkim.log" 2>&1 </dev/null
  $NS postfix -c "$ETC/postfix" start </dev/null >>"$VAR/start.log" 2>&1
  $NS dovecot -c "$ETC/dovecot/dovecot.conf" </dev/null >>"$VAR/start.log" 2>&1   # bez ovoga demon drži terminal
  for _ in $(seq 20); do $VAN bash -c 'exec 3<>/dev/tcp/10.50.0.25/587' 2>/dev/null && break; sleep 0.5; done
  echo "procesi: $(ip netns pids ruo5-mail | xargs -r ps -o comm= -p | sort -u | tr '\n' ' ')"
}

ispitaj() {
  [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 test"; exit 1; }
  local r d=/tmp/ruo5-mail-test; rm -rf "$d"; mkdir -p "$d"

  korak "1. DNS zapisi pošte (s5/p1): MX, SPF, DMARC, DKIM, PTR"
  echo "  MX:    $(dig +short @10.50.0.53 ruo.lab MX)"
  echo "  SPF:   $(dig +short @10.50.0.53 ruo.lab TXT)"
  echo "  DMARC: $(dig +short @10.50.0.53 _dmarc.ruo.lab TXT)"
  echo "  DKIM:  $(dig +short @10.50.0.53 ruo2026._domainkey.ruo.lab TXT | cut -c1-60)..."
  echo "  PTR:   10.50.0.25 -> $(dig +short @10.50.0.53 -x 10.50.0.25)"

  korak "2. TLS: certifikat odgovara imenu i potpisan je CA-om laba (STARTTLS na 587)"
  r="$($VAN openssl s_client -starttls smtp -connect mail.ruo.lab:587 -servername mail.ruo.lab \
        -verify_hostname mail.ruo.lab -CAfile "$CA" </dev/null 2>/dev/null)"
  echo "$r" | grep -E 'Verify return code|^New, ' | sed 's/^/  /'
  tvrdi "certifikat je ispravan za mail.ruo.lab" sadrzi "$r" 'Verify return code: 0 (ok)'

  korak "3. Negativni slučajevi: otvoreni relej i lozinka bez TLS-a"
  echo "\$ swaks --server mail.ruo.lab:25 --from neko@example.org --to zrtva@example.com   (iz ruo5-van, bez prijave)"
  r="$($VAN swaks --server mail.ruo.lab:25 --helo van.example.org --from neko@example.org --to zrtva@example.com 2>&1 || true)"
  echo "$r" | grep -E '^ *<\*\* ' | sed 's/^/  /'
  tvrdi "server odbija prosljeđivanje tuđe pošte (nije otvoreni relej)" sadrzi "$r" 'Relay access denied'
  echo "\$ swaks --server mail.ruo.lab:587 --auth ... (bez STARTTLS)"
  r="$($VAN swaks --server mail.ruo.lab:587 --helo laptop --from ana@ruo.lab --to ben@ruo.lab \
        --auth PLAIN --auth-user ana@ruo.lab --auth-password lozinka-ana-lab 2>&1 || true)"
  echo "$r" | grep -E '^ *<\*\* |\*\*\* ' | head -2 | sed 's/^/  /'
  tvrdi "prijava bez TLS-a nije moguća" sadrzi "$r" 'did not advertise authentication'

  korak "4. Slanje: ana@ruo.lab -> ben@ruo.lab preko submission (587, STARTTLS, prijava)"
  r="$($VAN swaks --server mail.ruo.lab:587 --helo laptop --tls --from ana@ruo.lab --to ben@ruo.lab \
        --auth PLAIN --auth-user ana@ruo.lab --auth-password lozinka-ana-lab \
        --header "Subject: Pozdrav iz sedmice 5" --body "Ovo je test poruka iz laba RuO." 2>&1 || true)"
  echo "$r" | grep -E '^<-  220 |^<~  235 |^<~  250 2\.0\.0 Ok' | sed 's/^/  /'
  tvrdi "poruka je primljena u red čekanja" sadrzi "$r" 'queued as'
  sleep 2

  korak "5. Čitanje: IMAP (143, STARTTLS) kao ben@ruo.lab, zaglavlja zadnje poruke"
  $VAN python3 - "$CA" "$d/poruka.eml" <<'PY'
import imaplib, ssl, sys
ctx = ssl.create_default_context(cafile=sys.argv[1])
m = imaplib.IMAP4("imap.ruo.lab", 143)
m.starttls(ssl_context=ctx)
m.login("ben@ruo.lab", "lozinka-ben-lab")
m.select("INBOX")
_, ids = m.search(None, "ALL")
broj = ids[0].split()
_, data = m.fetch(broj[-1], "(RFC822)")
open(sys.argv[2], "wb").write(data[0][1])
print(f"  INBOX: {len(broj)} poruka, TLS: {m.sock.version()}")
m.logout()
PY
  grep -E '^(From|To|Subject|DKIM-Signature):' "$d/poruka.eml" | cut -c1-100 | sed 's/^/  /'
  grep -A1 '^Received: from laptop' "$d/poruka.eml" | sed 's/^/  /' | cut -c1-100
  tvrdi "poruka je DKIM potpisana (d=ruo.lab, s=ruo2026)" sadrzi "$(cat "$d/poruka.eml")" 'd=ruo.lab; s=ruo2026'

  korak "6. DKIM: primalac provjerava potpis javnim ključem iz DNS-a"
  echo "\$ dkimverify < poruka.eml"
  tvrdi "potpis je ispravan" $VAN dkimverify < "$d/poruka.eml"
  sed 's/^Subject: .*/Subject: Izmijenjeno usput/' "$d/poruka.eml" > "$d/izmijenjena.eml"
  echo "\$ dkimverify < izmijenjena.eml   (promijenjen Subject)"
  tvrdi "izmjena poruke ruši potpis" nije $VAN dkimverify < "$d/izmijenjena.eml"

  korak "7. SPF i DMARC: smije li IP slati u ime ruo.lab, i da li se domene poklapaju s From"
  $VAN python3 -W ignore - "$d/poruka.eml" <<'PY'
import spf, dkim, sys
for ip, opis in (("10.50.0.25", "mail.ruo.lab (MX)"), ("10.50.0.66", "tuđi server")):
    rez = spf.check2(i=ip, s="ana@ruo.lab", h="test")
    print(f"  SPF {ip:<11} {opis:<18} -> {rez[0]}")
poruka = open(sys.argv[1], "rb").read()
dkim_ok = dkim.verify(poruka)
d = dkim.DKIM(poruka); d.verify()
from_dom = [l for l in poruka.decode().splitlines() if l.startswith("From:")][0].split("@")[1].strip(" >")
d_dom = d.domain.decode()
print(f"  DMARC: From domena={from_dom}, DKIM d={d_dom} (poravnato: {from_dom == d_dom}), DKIM={'pass' if dkim_ok else 'fail'}"
      f" -> {'pass' if dkim_ok and from_dom == d_dom else 'fail'}")
PY

  korak "8. Dnevnik Postfixa: put poruke (submission -> cleanup s DKIM -> LMTP u Dovecot)"
  grep -E 'postfix/(submission/smtpd|cleanup|lmtp).*(sasl_username|milter|message-id|status=sent)' "$VAR/postfix/maillog" \
    | tail -3 | sed -E 's/^.{16}//' | cut -c1-140 | sed 's/^/  /'
  tvrdi "isporučeno u sanduče ben@ruo.lab" grep -q 'status=sent (250 2.0.0 <ben@ruo.lab>' "$VAR/postfix/maillog"

  echo; [ "$GRESKE" = 0 ] && echo "Sve provjere su prošle." || { echo "Neuspjelih provjera: $GRESKE"; exit 1; }
}

dolje() {
  ip netns list | grep -qw ruo5-mail && {
    $NS postfix -c "$ETC/postfix" stop 2>/dev/null || true
    $NS doveadm -c "$ETC/dovecot/dovecot.conf" stop 2>/dev/null || true
    [ -f /run/ruo5/opendkim.pid ] && kill "$(cat /run/ruo5/opendkim.pid)" 2>/dev/null || true
    sleep 1; ip netns pids ruo5-mail | xargs -r kill 2>/dev/null || true   # ostaci (npr. prekinuto pokretanje)
    for _ in $(seq 20); do [ -z "$(ip netns pids ruo5-mail)" ] && break; sleep 0.25; done
  }
  rm -rf "$ETC" "$SPOOL" "$VAR/postfix" "$VAR/mail" "$VAR/dkim" "$VAR/ca" "$VAR"/*.log /run/ruo5 /tmp/ruo5-mail-test
  echo "mail zaustavljen i obrisan"
}

case "${1:-}" in
  provjera) provjera ;;
  up) gore ;;
  test) ispitaj ;;
  down) dolje ;;
  *) echo "Upotreba: $0 provjera | up | test | down"; exit 1 ;;
esac
