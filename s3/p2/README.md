# s3/p2: Upravljanje konfiguracijom s Ansible varijablama i Vault tajnama (Sedmica 3, zadatak 2)

Ovaj primjer demonstrira napredno upravljanje konfiguracijom pomoću Ansible-a: nadjačavanje zadanih varijabli role kroz hijerarhiju inventara (`group_vars`) i sigurno rukovanje osjetljivim podacima (tajnama) putem `ansible-vault` alata.

## Kontekst i zadatak

U praksi, Ansible role se pišu tako da budu generičke i višekratno iskoristive u različitim okruženjima (razvoj, test, produkcija). Zbog toga rola definiše razumne podrazumijevane vrijednosti (`defaults/main.yml`), dok se specifične vrijednosti za pojedine grupe servera zadaju na nivou inventara (`group_vars/`).

---

## Šta je urađeno

1. **Nadjačavanje varijable `naslov`:**
   U datoteci `s3/p2/group_vars/web/vars.yml` nadjačana je varijabla `naslov` (koja u `roles/webserver/defaults/main.yml` ima zadanu vrijednost `"web server"`):
   ```yaml
   naslov: "Računarstvo u oblaku: Web server s tajnama (group_vars)"
   ```
2. **Uvođenje nove tajne (`api_key`) pomoću `ansible-vault encrypt_string`:**
   - Za razliku od `vault_db_password` koja se nalazi u zasebno šifrovanoj datoteci `vault.yml`, nova tajna `api_key` je šifrovana na nivou stringa naredbom:
     ```bash
     ansible-vault encrypt_string --vault-password-file .vault_pass 'kljuc' --name 'api_key'
     ```
   - Dobijeni `!vault |` blok je direktno smješten u `s3/p2/group_vars/web/vars.yml`, što omogućava sigurno čuvanje unutar Git repozitorija bez rizika od otkrivanja tajne.
3. **Propagacija u okolinu aplikacije:**
   U šablonu `s3/p2/roles/webserver/templates/app.env.j2` dodata je nova varijabla okruženja:
   ```jinja2
   API_KEY={{ api_key }}
   ```

---

## Teorijski koncepti

### 1. Hijerarhija prioriteta varijabli (Variable Precedence)
Ansible posjeduje strogo definisan redoslijed prioriteta varijabli:
1. `role defaults` (`defaults/main.yml`) – najniži prioritet unutar role; služi samo kao fallback.
2. `inventory group_vars` (`group_vars/web/vars.yml`) – nadjačava `role defaults`.
3. `inventory host_vars` – nadjačava `group_vars`.
4. `extra vars` (`-e`) – najviši prioritet pri izvršavanju.

Korištenjem `group_vars/web/vars.yml`, rola `webserver` ostaje čista i nepromijenjena, dok se specifična konfiguracija za web nodove definiše na nivou grupe.

### 2. Šifrovanje pojedinačnih stringova (`ansible-vault encrypt_string`)
Pored šifrovanja cijelih datoteka (`ansible-vault encrypt`), Ansible omogućava i šifrovanje pojedinačnih osjetljivih stringova direktno u YAML datotekama:

```bash
ansible-vault encrypt_string --vault-password-file .vault_pass 'tajni-api-kljuc-12345' --name 'vault_api_key'
```

Ova komanda generiše blok poput:
```yaml
vault_api_key: !vault |
          $ANSIBLE_VAULT;
```
koji se može direktno commitati u Git, jer niko bez lozinke iz `.vault_pass` ne može pročitati originalni sadržaj.

---

## Pokretanje i provjera

Pokretanje i provjera se vrše kroz Makefile:

```bash
# 1. Priprema lozinke i šifrovane vault.yml datoteke (lokalno, van Gita)
make s3-p2-vault

# 2. Pregled šifrovanih vrijednosti i provjera sintakse (dry-run)
make s3-p2


