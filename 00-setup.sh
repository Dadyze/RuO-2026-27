#!/usr/bin/env bash
# 00-setup.sh: prva skripta. Instalira i podešava alate za primjere u ovom repozitoriju.
# Podržano: Ubuntu 22.04/24.04 i Debian (i WSL2 Ubuntu). Pokretati kao običan korisnik (sudo se traži po potrebi).
#
#   ./00-setup.sh                  instalacija svega
#   SKIP_LIBVIRT=1 ./00-setup.sh   bez KVM/libvirt (npr. ako nema /dev/kvm)
#   SKIP_K8S=1 ./00-setup.sh       bez kubectl i kind
#   INSTALL_DOCKER=1 ./00-setup.sh instalira Docker Engine ako ga nema (u WSL2 je jednostavnije Docker Desktop)
#
# Skripta je idempotentna: sigurno se može pokrenuti više puta.
set -euo pipefail

KIND_VERSION="${KIND_VERSION:-v0.24.0}"
SKIP_LIBVIRT="${SKIP_LIBVIRT:-0}"
SKIP_K8S="${SKIP_K8S:-0}"
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_step=$'\033[1;36m'; c_off=$'\033[0m'
step() { printf '\n%s== %s%s\n' "$c_step" "$*" "$c_off"; }
ok()   { printf '  %sok%s    %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!!%s    %s\n' "$c_warn" "$c_off" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -ne 0 ] || { echo "Ne pokretati kao root; skripta sama koristi sudo."; exit 1; }
[ "$(uname -s)" = "Linux" ] || { echo "Potreban je Linux ili WSL2."; exit 1; }
have apt-get || { echo "Skripta podržava samo apt (Ubuntu/Debian)."; exit 1; }
sudo -v

IN_WSL=0; grep -qi microsoft /proc/version 2>/dev/null && IN_WSL=1
HAS_SYSTEMD=0; [ "$(ps -p 1 -o comm= 2>/dev/null || true)" = "systemd" ] && HAS_SYSTEMD=1
NEED_RELOGIN=0

step "1/8 Provjera okruženja"
ok "$(. /etc/os-release && echo "$PRETTY_NAME")"
if [ "$IN_WSL" = 1 ]; then
  ok "WSL2 detektovan"
  if [ "$HAS_SYSTEMD" = 0 ]; then
    warn "systemd nije uključen (potreban za libvirt)."
    if ! grep -qs '^\s*systemd\s*=\s*true' /etc/wsl.conf; then
      printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
      warn "dodano u /etc/wsl.conf. U PowerShellu pokrenuti: wsl --shutdown, pa ponovo otvoriti Ubuntu i ponovo ./00-setup.sh"
    fi
  fi
fi

step "2/8 Osnovni paketi (git, make, curl, ansible)"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git make curl wget gnupg lsb-release ca-certificates software-properties-common \
  python3 python3-yaml openssh-client ansible \
  iproute2 nftables wireguard-tools
# wireguard-go: korisnička zamjena ako kernel nema WireGuard modul (s4/p3); nije obavezan
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-go || warn "wireguard-go nije dostupan (potreban samo bez kernelskog modula)"
ok "git, make, curl, ansible, iproute2, nftables, wireguard-tools"

step "3/8 HashiCorp repozitorij: Terraform i Packer"
KEYRING=/usr/share/keyrings/hashicorp-archive-keyring.gpg
if [ ! -f "$KEYRING" ]; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o "$KEYRING"
fi
echo "deb [signed-by=$KEYRING] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y terraform packer
ok "terraform i packer"

step "4/8 KVM i libvirt"
if [ "$SKIP_LIBVIRT" = 1 ]; then
  warn "preskočeno (SKIP_LIBVIRT=1)"
else
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    qemu-system-x86 libvirt-daemon-system libvirt-clients virtinst genisoimage
  for g in libvirt kvm; do
    case " $(id -nG "$USER") " in
      *" $g "*) ;;
      *) sudo usermod -aG "$g" "$USER"; NEED_RELOGIN=1 ;;
    esac
  done
  if [ "$HAS_SYSTEMD" = 1 ]; then
    sudo systemctl enable --now libvirtd
    # default pool i mreža koje očekuju Terraform primjeri
    V="sudo virsh -c qemu:///system"
    if ! $V pool-info default >/dev/null 2>&1; then
      $V pool-define-as default dir --target /var/lib/libvirt/images
      $V pool-autostart default
    fi
    $V pool-start default >/dev/null 2>&1 || true
    $V net-autostart default >/dev/null 2>&1 || true
    $V net-start default >/dev/null 2>&1 || true
    ok "libvirt radi, pool i mreža 'default' postoje"
  else
    warn "systemd nije aktivan: libvirt servis nije pokrenut"
  fi
  if [ -e /dev/kvm ]; then ok "/dev/kvm postoji"; else warn "nema /dev/kvm: VM primjeri ostaju na nivou plan/validate"; fi
fi

step "5/8 Docker"
if have docker && docker version >/dev/null 2>&1; then
  ok "docker radi: $(docker --version)"
elif [ "$INSTALL_DOCKER" = 1 ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  # Compose v2 plugin: u Ubuntu 24.04 je paket docker-compose-v2; starije verzije ga nemaju
  if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2; then
    warn "docker-compose-v2 nije dostupan na ovoj verziji; preporuka: Docker Desktop ili Ubuntu 24.04"
  fi
  sudo usermod -aG docker "$USER"; NEED_RELOGIN=1
  [ "$HAS_SYSTEMD" = 1 ] && sudo systemctl enable --now docker
  ok "Docker Engine instaliran"
else
  warn "docker nije dostupan. U WSL2: instalirati Docker Desktop i uključiti WSL integraciju;"
  warn "ili pokrenuti: INSTALL_DOCKER=1 ./00-setup.sh"
fi

step "6/8 kubectl i kind"
if [ "$SKIP_K8S" = 1 ]; then
  warn "preskočeno (SKIP_K8S=1)"
else
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  if ! have kubectl; then
    curl -fsSL -o "$TMP/kubectl" "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install "$TMP/kubectl" /usr/local/bin/kubectl
  fi
  if ! have kind; then
    curl -fsSL -o "$TMP/kind" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
    sudo install "$TMP/kind" /usr/local/bin/kind
  fi
  ok "kubectl i kind"
fi

step "7/8 SSH ključ za virtualne mašine"
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  ok "~/.ssh/id_ed25519 već postoji"
else
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$USER@ruo"
  ok "napravljen ~/.ssh/id_ed25519"
fi

step "8/8 Provjera"
for t in git make terraform packer ansible docker kubectl kind virsh nft wg ip; do
  if have "$t"; then ok "$t"; else warn "$t nije instaliran"; fi
done
# sed -n 1p cita cijeli ulaz (head -1 bi uz pipefail prekinuo skriptu zbog SIGPIPE)
have terraform && terraform version | sed -n 1p
have ansible && ansible --version | sed -n 1p
have packer && packer version | sed -n 1p
true

printf '\n%sGotovo.%s Sljedeći koraci: make check, make help, make s2-p1\n' "$c_ok" "$c_off"
if [ "$NEED_RELOGIN" = 1 ]; then
  warn "Dodani ste u nove grupe (libvirt/kvm/docker). Odjavite se i prijavite ponovo (WSL: wsl --shutdown) prije korištenja VM-ova."
fi
