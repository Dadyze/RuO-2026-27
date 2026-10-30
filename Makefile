# Računarstvo u oblaku 2026/27: primjeri s predavanja (IaC)
# Pokretanje: `make help`. Naredbe se ispisuju prije izvršavanja, da se vidi šta se radi.
# Napomena: umjesto tabulatora koristi se ">" kao prefiks naredbi (.RECIPEPREFIX).

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.RECIPEPREFIX := >
.DEFAULT_GOAL := help

# -K traži sudo lozinku (become); ako sudo ne traži lozinku: make ANSIBLE_ARGS= ...
ANSIBLE_ARGS ?= -K
EX ?=

banner = printf '\n\033[1;36m== %s\033[0m\n' '$(1)'
# provjera alata prije izvršavanja: jasna poruka umjesto kriptične greške
need = command -v $(1) >/dev/null || { echo "Nedostaje '$(1)'. Pokreni: ./00-setup.sh"; exit 1; }
need_libvirt = virsh -c qemu:///system list >/dev/null 2>&1 || { echo "libvirt ne radi (virsh -c qemu:///system list). Pokreni ./00-setup.sh i pogledaj README.md (systemd/KVM)"; exit 1; }

.PHONY: help setup check run all ssh-key safe-all clean-all \
  s2-p1 s2-p1-clean s2-p2 s2-p3 s2-p3-apply s2-p3-clean \
  s2-p4 s2-p4-build s2-p4-vm s2-p4-clean \
  s3-p1 s3-p1-apply s3-p2-vault s3-p2 s3-p2-apply s3-p3 s3-p3-apply s3-p3-clean \
  s3-p4 s3-p4-config s3-p4-persist s3-p4-clean s3-p5 s3-p5-up s3-p5-heal s3-p5-clean \
  s4-p1 s4-p1-lab s4-p1-clean s4-p2 s4-p2-up s4-p2-clean s4-p3 s4-p3-apply \
  s4-p4 s4-p4-apply s4-p4-clean s4-clean

##@ Pomoć
help: ## ovaj popis
> @awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n\033[1m%s\033[0m\n", substr($$0,5)} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
> @printf '\nPrimjer: make s2-p1   ili   make run EX=s2-p1\n'

setup: ## instalira sve alate (00-setup.sh)
> ./00-setup.sh

check: ## provjera da li su alati instalirani
> @for t in git make terraform packer ansible docker kubectl kind virsh nft; do \
>   if command -v $$t >/dev/null; then printf '  \033[32mok\033[0m     %s\n' $$t; else printf '  \033[33mnema\033[0m   %s\n' $$t; fi; done

run: ## make run EX=s2-p1 (isto što i make s2-p1)
> @test -n "$(EX)" || { echo "Upotreba: make run EX=s2-p1"; exit 1; }
> @$(MAKE) --no-print-directory $(EX)

ssh-key:
> @test -f ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

##@ Sedmica 2: IaC i virtualne mašine kao kod
s2-p1: ## Terraform bez oblaka: idempotentnost, state, drift (lokalno, besplatno)
> @$(call need,terraform)
> @$(call banner,1. init i plan)
> cd s2/p1 && terraform init -input=false && terraform plan
> @$(call banner,2. apply: kreira datoteku)
> cd s2/p1 && terraform apply -auto-approve
> @$(call banner,3. apply ponovo: ocekujemo 0 added / 0 changed = idempotentnost)
> cd s2/p1 && terraform apply -auto-approve && cat pozdrav.txt && terraform state list
> @$(call banner,4. promjena varijable: plan pokazuje zamjenu resursa)
> cd s2/p1 && terraform plan -var ime=Studenti | grep -E 'forces replacement|Plan:' || true
> @$(call banner,5. DRIFT: datoteku mijenjamo rucno izvan Terraforma)
> echo "ručno izmijenjeno" > s2/p1/pozdrav.txt
> cd s2/p1 && terraform plan -refresh-only
> @$(call banner,6. apply vraca stvarno stanje na ono iz koda)
> cd s2/p1 && terraform apply -auto-approve && cat pozdrav.txt
s2-p1-clean: ## uklanja resurse i state za s2-p1
> cd s2/p1 && { terraform destroy -auto-approve || true; } && rm -rf .terraform terraform.tfstate* pozdrav.txt

s2-p2: ## cloud-init: provjera user-data
> @head -1 s2/p2/user-data | grep -qx '#cloud-config' && echo "prvi red je #cloud-config"
> @if command -v cloud-init >/dev/null; then cloud-init schema --config-file s2/p2/user-data; \
>  else python3 -c "import yaml; yaml.safe_load(open('s2/p2/user-data')); print('YAML ispravan (cloud-init nije instaliran, provjeren samo YAML)')"; fi

s2-p3: ssh-key ## Terraform + libvirt VM: init, validate, PLAN (bez kreiranja)
> @$(call need,terraform)
> @$(call need_libvirt)
> cd s2/p3 && terraform init -input=false && terraform validate && terraform plan -out=tfplan
s2-p3-apply: s2-p3 ## [opcionalno] stvarno kreira VM (traži KVM/libvirt)
> cd s2/p3 && terraform apply tfplan && terraform output
s2-p3-clean: ## uklanja VM i state
> cd s2/p3 && { terraform destroy -auto-approve || true; } && rm -rf .terraform terraform.tfstate* tfplan

s2-p4: ## Packer: init i validate (bez izgradnje slike)
> @$(call need,packer)
> cd s2/p4 && packer init . && packer validate .
s2-p4-build: s2-p4 ## [opcionalno] gradi sliku (~4 min, ~640 MB, traži KVM)
> cd s2/p4 && packer build .
s2-p4-vm: ssh-key ## plan VM-a iz Packer slike (slika mora postojati: s2-p4-build)
> @$(call need,terraform)
> @$(call need_libvirt)
> @test -f s2/p4/output/ruo-base.qcow2 || { echo "Slika ne postoji: prvo make s2-p4-build"; exit 1; }
> cd s2/p4/vm && terraform init -input=false && terraform validate && terraform plan
s2-p4-clean: ## briše sliku i state VM-a
> rm -rf s2/p4/output; cd s2/p4/vm && { terraform destroy -auto-approve || true; } && rm -rf .terraform terraform.tfstate*

##@ Sedmica 3: konfiguracija i kontejneri kao kod
s3-p1: ## Ansible: ping, syntax-check, --check --diff (bez izmjena sistema)
> @$(call need,ansible)
> cd s3/p1 && ansible -i inventory.ini web -m ping
> cd s3/p1 && ansible-playbook -i inventory.ini site.yml --syntax-check
> cd s3/p1 && ansible-playbook -i inventory.ini site.yml $(ANSIBLE_ARGS) --check --diff
s3-p1-apply: ## [opcionalno] stvarno instalira nginx; pokreće 2x (idempotentnost)
> @$(call banner,1. izvrsavanje: ocekujemo changed > 0)
> cd s3/p1 && ansible-playbook -i inventory.ini site.yml $(ANSIBLE_ARGS)
> @$(call banner,2. izvrsavanje: ocekujemo changed=0)
> cd s3/p1 && ansible-playbook -i inventory.ini site.yml $(ANSIBLE_ARGS)
> curl -s http://localhost

s3-p2-vault: ## pravi lab Vault lozinku i šifrovanu tajnu (nije u Gitu)
> @$(call need,ansible-vault)
> cd s3/p2 && test -f .vault_pass || { echo "lozinka-za-vault-lab" > .vault_pass; chmod 600 .vault_pass; }
> cd s3/p2 && test -f group_vars/web/vault.yml || { grep -v '^#' group_vars/web/vault.yml.example > group_vars/web/vault.yml && ansible-vault encrypt group_vars/web/vault.yml; }
s3-p2: s3-p2-vault ## Role + Vault: pregled šifrovane datoteke, syntax-check, --check
> @$(call banner,sifrovana datoteka (prvih 60 znakova))
> cd s3/p2 && head -c 60 group_vars/web/vault.yml; echo
> @$(call banner,ansible-vault view)
> cd s3/p2 && ansible-vault view group_vars/web/vault.yml
> cd s3/p2 && ansible-playbook site.yml --syntax-check
> cd s3/p2 && ansible-playbook site.yml $(ANSIBLE_ARGS) --check --diff
s3-p2-apply: s3-p2-vault ## [opcionalno] stvarno primjenjuje rolu
> cd s3/p2 && ansible-playbook site.yml $(ANSIBLE_ARGS)

s3-p3: s3-p2-vault ssh-key ## Terraform + Ansible: PLAN i syntax-check (bez kreiranja VM-a)
> @$(call need,terraform)
> @$(call need,ansible-playbook)
> @$(call need_libvirt)
> mkdir -p s3/p3/group_vars/web && cp s3/p2/group_vars/web/vault.yml s3/p3/group_vars/web/vault.yml
> cd s3/p3 && terraform init -input=false && terraform validate && terraform plan -out=tfplan
> cd s3/p3 && ansible-playbook -i localhost, site.yml --syntax-check
s3-p3-apply: s3-p3 ## [opcionalno] kreira VM i konfiguriše je (deploy.sh)
> cd s3/p3 && bash deploy.sh && curl -s http://$$(terraform output -raw ip)
s3-p3-clean: ## uklanja VM, inventory i state
> cd s3/p3 && { terraform destroy -auto-approve || true; } && rm -rf .terraform terraform.tfstate* tfplan inventory.ini

s3-p4-config: ## Compose: samo provjera datoteke
> @$(call need,docker)
> cd s3/p4 && docker compose config -q && echo "compose.yaml je ispravan"
s3-p4: s3-p4-config ## Dockerfile + Compose: build, up, 3 posjete (lokalno, besplatno)
> cd s3/p4 && docker compose up -d --build --wait
> cd s3/p4 && docker compose ps
> @$(call banner,3 zahtjeva: brojac raste)
> for i in 1 2 3; do curl -s localhost:8080; done
> @$(call banner,slojevi slike)
> docker image history ruo/brojac:1.0
s3-p4-persist: ## down pa up: podaci u volumenu prežive
> cd s3/p4 && docker compose down && docker compose up -d --wait
> curl -s localhost:8080
s3-p4-clean: ## down -v (briše i volumen)
> cd s3/p4 && docker compose down -v

s3-p5: ## Kubernetes: dry-run manifesta (bez klastera)
> @$(call need,kubectl)
> kubectl apply --dry-run=client --validate=false -f s3/p5/web.yaml
s3-p5-up: ## [opcionalno] kind klaster + apply + curl
> @$(call need,kind)
> @$(call need,kubectl)
> @$(call need,docker)
> kind get clusters | grep -qx ruo || kind create cluster --name ruo
> kubectl apply -f s3/p5/web.yaml
> kubectl rollout status deploy/web --timeout=120s
> kubectl get pods -o wide
> kubectl port-forward svc/web 8081:80 >/dev/null & PF=$$!; sleep 2; curl -s localhost:8081; kill $$PF
s3-p5-heal: ## briše jedan Pod: Deployment ga vraća
> kubectl delete pod $$(kubectl get pods -o name | head -1)
> kubectl get pods
s3-p5-clean: ## briše kind klaster
> kind delete cluster --name ruo

##@ Sedmica 4: mreža i vatrozid kao kod (vježbe su u Linux network namespace-ovima; naredbe -lab/-up/-apply traže sudo)
s4-p1: ## osnove: pregled mreže računara (ip link/addr/route), samo čita
> bash s4/p1/osnove.sh pregled
s4-p1-lab: ## [opcionalno] vježba: dodaj/promijeni/obriši adresu, sučelje i rutu (PAUZA=1 čeka Enter)
> sudo PAUZA=$(PAUZA) bash s4/p1/osnove.sh vjezba
s4-p1-clean: ## briše namespace-ove vježbe
> -sudo bash s4/p1/osnove.sh down

s4-p2: ## mrežni lab: ispis naredbi (DRY=1), ništa se ne mijenja
> DRY=1 bash s4/p2/lab.sh up
s4-p2-up: ## [opcionalno] stvara ruter + web/app/db segmente (namespace-ovi)
> sudo bash s4/p2/lab.sh up && sudo bash s4/p2/lab.sh status
s4-p2-clean: ## briše lab
> -sudo bash s4/p2/lab.sh down

s4-p3: ## nftables: provjera sintakse datoteke (nft -c), bez učitavanja
> @$(call need,nft)
> sudo nft -c -f s4/p3/firewall.nft && echo "firewall.nft je ispravan"
s4-p3-apply: s4-p3 ## [opcionalno] učita pravila u ruter i pokrene matricu povezivosti (traži s4-p2-up)
> @$(call banner,PRIJE: ravna mreža, sve je dozvoljeno)
> sudo bash s4/p3/test.sh
> sudo ip netns exec ruo-rtr nft -f s4/p3/firewall.nft
> @$(call banner,POSLIJE: samo ono što politika dozvoljava)
> sudo bash s4/p3/test.sh

s4-p4: ## Ansible rola vatrozida iz podataka: syntax-check, --check --diff
> @$(call need,ansible-playbook)
> cd s4/p4 && ansible-playbook site.yml --syntax-check
> cd s4/p4 && ansible-playbook site.yml $(ANSIBLE_ARGS) -e '{"fw_instaliraj_paket": false}' --check --diff
s4-p4-apply: ## [opcionalno] primijeni rolu na ruter iz laba, dva puta (idempotentnost), pa matrica (traži s4-p2-up)
> @$(call banner,1. izvrsavanje: ocekujemo changed > 0)
> cd s4/p4 && ansible-playbook site.yml $(ANSIBLE_ARGS) -e '{"fw_instaliraj_paket": false}'
> @$(call banner,2. izvrsavanje: ocekujemo changed=0)
> cd s4/p4 && ansible-playbook site.yml $(ANSIBLE_ARGS) -e '{"fw_instaliraj_paket": false}'
> sudo bash s4/p3/test.sh
s4-p4-clean: ## briše generisana pravila
> sudo rm -f /etc/nftables.d/ruo.nft
s4-clean: s4-p1-clean s4-p2-clean s4-p4-clean ## čisti cijelu sedmicu 4

##@ Skupno
all: check s2-p1 s2-p2 s2-p3 s2-p4 s3-p1 s3-p2 s3-p3 s3-p4 s3-p5 s4-p1 s4-p2 s4-p3 s4-p4 ## svi primjeri redom, sekvencijalno (idempotentno: može se ponoviti)
> @$(call banner,SVI PRIMJERI ZAVRSENI)
safe-all: ## sve što ne mijenja sistem (plan/validate/--check/dry-run)
> $(MAKE) --no-print-directory s2-p2 s2-p3 s2-p4 s3-p1 s3-p2 s3-p3 s3-p4-config s3-p5 s4-p1 s4-p2 s4-p3 s4-p4
clean-all: ## čišćenje svih primjera
> -$(MAKE) --no-print-directory s2-p1-clean s2-p3-clean s2-p4-clean s3-p3-clean s3-p4-clean s3-p5-clean s4-clean
