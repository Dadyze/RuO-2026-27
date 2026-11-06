#!/usr/bin/env bash
# s5/p4: provjera SFTP servera. Klijent je računar (10.50.0.1, dozvoljen), a ruo5-van (10.50.0.66) je
# "vanjski" računar koji vatrozid odbija. Pokreće se iz make s5-p4-apply (traži root zbog ip netns).
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
cd "$(dirname "$0")"
GRESKE=0
korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
tvrdi() { local o="$1"; shift; if "$@"; then echo "  ok: $o"; else echo "  NIJE OK: $o"; GRESKE=$((GRESKE + 1)); fi; }
sadrzi() { grep -q -- "$2" <<< "$1"; }
nije_sadrzi() { ! grep -q -- "$2" <<< "$1"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# known_hosts iz ključa servera: klijent provjerava da razgovara s pravim serverom (nema "yes/no" pitanja)
echo "10.50.0.22 $(cut -d' ' -f1,2 /etc/ruo5/sftp/ssh_host_ed25519_key.pub)" > "$T/known_hosts"
SSH_OPT=(-o UserKnownHostsFile="$T/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=3)
sftp_kao() { # korisnik + naredbe sa standardnog ulaza
  sftp "${SSH_OPT[@]}" -i "kljucevi/$1" -b - "$1@10.50.0.22" 2>&1
}

korak "1. Otisak ključa servera (provjerava se pri svakom spajanju)"
ssh-keygen -lf /etc/ruo5/sftp/ssh_host_ed25519_key.pub | sed 's/^/  /'

korak "2. ruo-ana: sesija počinje u /upload; korijen (/) je chroot, a ne korijen servera"
echo "izvještaj sedmice 5" > "$T/izvjestaj.txt"
r="$(sftp_kao ruo-ana <<EOF
pwd
put $T/izvjestaj.txt
ls -l
cd /
ls -la
EOF
)"
echo "$r" | sed "s#$T/##; s/^/  /"
tvrdi "datoteka je na serveru u /srv/ruo5-sftp/ruo-ana/upload" test -f /srv/ruo5-sftp/ruo-ana/upload/izvjestaj.txt
tvrdi "u korijenu sesije postoji samo upload" test "$(echo "$r" | awk '/^sftp> ls -la/{f=1;next} f && /^d/{print $NF}' | tr '\n' ' ')" = ". .. upload "

korak "3. ruo-ana: izvan chroota se ne vidi ništa, a u korijen chroota se ne može pisati"
r="$(sftp_kao ruo-ana <<EOF
-cd /etc
-get /etc/passwd $T/p
-put $T/izvjestaj.txt /izvjestaj.txt
EOF
)"
echo "$r" | grep -v '^sftp>' | sed 's/^/  /'
tvrdi "/etc servera nije dostupan" sadrzi "$r" 'No such file or directory'
tvrdi "pisanje u korijen chroota je odbijeno" sadrzi "$r" 'Permission denied'

korak "4. ruo-ben: vidi samo svoj direktorij (ne vidi Aninu datoteku)"
r="$(printf 'ls /\nls /upload\n' | sftp_kao ruo-ben)"
echo "$r" | sed 's/^/  /'
tvrdi "ruo-ben ne vidi izvjestaj.txt" nije_sadrzi "$r" 'izvjestaj'

korak "5. Shell i lozinke nisu dozvoljeni"
r="$(ssh "${SSH_OPT[@]}" -i kljucevi/ruo-ana ruo-ana@10.50.0.22 id 2>&1)"
echo "  \$ ssh ruo-ana@10.50.0.22 id  ->  $(echo "$r" | tail -1)"
tvrdi "naredba se ne izvršava (samo SFTP)" sadrzi "$r" 'only sftp\|This service allows sftp'
r="$(ssh -T "${SSH_OPT[@]}" -o PubkeyAuthentication=no -o PreferredAuthentications=password ruo-ana@10.50.0.22 2>&1)"
echo "  \$ ssh -o PreferredAuthentications=password ...  ->  $r"
tvrdi "prijava lozinkom se ne nudi" sadrzi "$r" 'Permission denied (publickey)'

korak "6. Vatrozid: iz ruo5-van (10.50.0.66) SSH port nije dostupan"
if ip netns exec ruo5-van timeout 3 bash -c 'exec 3<>/dev/tcp/10.50.0.22/22' 2>/dev/null; then r=otvoren; else r=blokiran; fi
echo "  ruo5-van -> 10.50.0.22:22  $r"
tvrdi "pristup izvana je blokiran" test "$r" = blokiran
ip netns exec ruo5-sftp nft list chain inet ruo5sftp input | grep counter | sed 's/^ */  /'

korak "7. Dnevnik sshd-a: ko se prijavio, odakle i kojim ključem"
grep 'Accepted publickey' /var/lib/ruo5/sftp-sshd.log | tail -2 | cut -c1-110 | sed 's/^/  /'

echo; [ "$GRESKE" = 0 ] && echo "Sve provjere su prošle." || { echo "Neuspjelih provjera: $GRESKE"; exit 1; }
