#!/usr/bin/env bash
# s6/p1: block storage na računaru. "Disk" je obična datoteka prikačena kao loop uređaj: jezgra je vidi kao
# blok uređaj, isto kao što VM vidi volumen iz oblaka (AWS EBS, Azure Managed Disk) ili qcow2 iz sedmice 2.
#
#   ./disk.sh pregled     samo čita: diskovi, particije, datotečni sistemi i montiranja (ne traži root)
#   ./disk.sh vjezba      napravi disk, datotečni sistem, montiraj, otkači/prikači, proširi (root)
#                         PAUZA=1: čeka Enter nakon svakog koraka
#   ./disk.sh down        otkači i obriši disk vježbe
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
PAUZA="${PAUZA:-0}"
SLIKA=/var/tmp/ruo6-disk.img      # "volumen": datoteka na disku računara
MNT=/mnt/ruo6                     # gdje ga montiramo

korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
kmd() { echo "\$ $*"; "$@"; return 0; }
pauza() { [ "$PAUZA" = 1 ] && read -r -p "   (Enter za nastavak) " _ || true; }
loop() { losetup -j "$SLIKA" | cut -d: -f1 | head -1; }

pregled() {
  korak "1. Blok uređaji (lsblk): diskovi, particije, veličine i gdje su montirani"
  kmd lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS
  korak "2. Datotečni sistemi (df -hT): tip, veličina, zauzeće"
  kmd df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay
  korak "3. Montiranja (findmnt): koji uređaj je montiran gdje i s kojim opcijama"
  kmd findmnt -D -t ext4,xfs,btrfs,vfat,9p,nfs,nfs4,drvfs
}

vjezba() {
  [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 vjezba"; exit 1; }
  down >/dev/null 2>&1

  korak "1. Novi volumen od 256 MB: datoteka je 'rijetka' (sparse), pa na disku još ne zauzima prostor"
  kmd truncate -s 256M "$SLIKA"
  kmd ls -lsh "$SLIKA"
  echo "   (prvi broj je stvarno zauzeće, a 256M je veličina koju vidi uređaj: thin provisioning)"; pauza

  korak "2. Prikačivanje (attach): datoteka postaje blok uređaj /dev/loopN, bez datotečnog sistema"
  kmd losetup -f --show "$SLIKA"
  L="$(loop)"
  kmd lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS "$L"
  echo "   (FSTYPE je prazan: uređaj je samo niz blokova, ništa ne zna o datotekama)"; pauza

  korak "3. Datotečni sistem (mkfs.ext4) i montiranje: tek sada postoje direktoriji i datoteke"
  kmd mkfs.ext4 -q -L ruo6-podaci "$L"
  kmd mkdir -p "$MNT"
  kmd mount "$L" "$MNT"
  echo "narudzba 1001" > "$MNT/narudzbe.txt"; echo "\$ echo 'narudzba 1001' > $MNT/narudzbe.txt"
  kmd df -hT "$MNT"
  kmd ls -lsh "$SLIKA"; pauza

  korak "4. Otkačivanje i ponovno prikačivanje (detach/attach): podaci žive na volumenu, ne na 'VM-u'"
  kmd umount "$MNT"
  kmd losetup -d "$L"
  echo "   (volumen nije prikačen nigdje; u oblaku bi se sada mogao prikačiti drugoj VM)"
  kmd losetup -f --show "$SLIKA"
  L="$(loop)"
  kmd mount "$L" "$MNT"
  kmd cat "$MNT/narudzbe.txt"; pauza

  korak "5. Proširenje volumena bez gašenja: veći uređaj, pa veći datotečni sistem (resize2fs, online)"
  kmd df -h "$MNT"
  kmd truncate -s 512M "$SLIKA"
  kmd losetup -c "$L"
  kmd lsblk -o NAME,SIZE "$L"
  echo "   (uređaj je 512M, ali datotečni sistem još zna samo za 256M)"
  echo "\$ resize2fs $L"
  if ! resize2fs "$L" 2>&1; then
    # neka okruženja (kontejneri, stariji WSL kerneli) ne dozvoljavaju online proširenje: radi se offline
    echo "   (online proširenje ovdje nije dozvoljeno: offline, uz kratko otkačivanje)"
    kmd umount "$MNT"
    kmd e2fsck -fp "$L"
    kmd resize2fs "$L"
    kmd mount "$L" "$MNT"
  fi
  kmd df -h "$MNT"
  kmd cat "$MNT/narudzbe.txt"; pauza

  korak "6. Kraj: $MNT ostaje montiran za pregled; briše ga: make s6-p1-clean"
}

down() {
  mountpoint -q "$MNT" && umount "$MNT" && echo "umount $MNT"
  for l in $(losetup -j "$SLIKA" 2>/dev/null | cut -d: -f1); do losetup -d "$l" && echo "losetup -d $l"; done
  rm -f "$SLIKA"; rmdir "$MNT" 2>/dev/null || true
}

case "${1:-}" in
  pregled) pregled ;;
  vjezba) vjezba ;;
  down) [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 down"; exit 1; }; down ;;
  *) echo "Upotreba: $0 pregled | vjezba | down"; exit 1 ;;
esac
