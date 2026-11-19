# s5/p2: Terraform DNS provider (RFC 2136) – Cache servis i SRV zapisi (Sedmica 5, zadatak 3)

Ovaj primjer demonstrira upravljanje DNS zapisima kao kodom (DNS-as-Code) korištenjem HashiCorp Terraform `dns` providera 

## Kontekst i zadatak

Zadatak za samostalni rad br. 3 zahtijeva:
1. U `s5/p2/main.tf` dodati servis `cache = ["10.40.4.10"]` u varijablu `servisi`.
2. Dodati resurs za `SRV` zapis za otkrivanje servisa (`dns_srv_record_set`).
3. Primijeniti konfiguraciju dva puta i pokazati idempotentnost (izlaz drugog izvršavanja).

---

## Šta je urađeno

1. **Dodavanje `cache` servisa:**
   U mapi varijable `servisi` u `s5/p2/main.tf` definisan je novi servis iz sedmice 4:
   ```hcl
   variable "servisi" {
     type = map(list(string))
     default = {
       web   = ["10.40.1.10", "10.40.1.11"]
       app   = ["10.40.2.10"]
       db    = ["10.40.3.10"]
       cache = ["10.40.4.10"]
     }
   }
   ```
   Kroz postojeći `dns_a_record_set.servis` resurs koji koristi `for_each = var.servisi`, Terraform automatski kreira `cache.oblak.ruo.lab. -> 10.40.4.10`.

2. **Kreiranje `SRV` zapisa (`dns_srv_record_set`):**
   Dodat je novi resurs za automatsko otkrivanje Redis/cache servisa:
   ```hcl
   resource "dns_srv_record_set" "cache_srv" {
     zone = var.zona
     name = "_redis._tcp"
     srv {
       priority = 10
       weight   = 10
       port     = 6379
       target   = "cache.${var.zona}"
     }
     ttl = 300
   }
   ```

3. **Izlaz za verifikaciju:**
   Dodan je izlaz `output "srv"` koji prikazuje mapiranje SRV zapisa na FQDN i port.

---

## Teorijski koncepti

### 1. Dinamički DNS putem RFC 2136
Umjesto ručnog editovanja zonskih datoteka i ponovnog učitavanja (`rndc reload`), Terraform koristi protokol **RFC 2136**. Sve operacije (dodavanje, izmjena, brisanje zapisa) šalju se kao mrežne DNS UPDATE poruke na primarni poslužitelj (`10.50.0.53`). Transakcije su kriptografski potpisane TSIG ključem (`ruo-tf`) algoritma `hmac-sha256`, pri čemu BIND `update-policy` ograničava taj ključ isključivo na poddomenu `oblak.ruo.lab.`.

### 2. Service Discovery putem SRV zapisa (RFC 2782)
Standardni A/AAAA zapisi pružaju isključivo preslikavanje imena u IP adresu. Nasuprot tome, **SRV (Service) zapis** definiše:
- Ime servisa i protokol: `_redis._tcp`
- Prioritet (`priority = 10`): omogućava definisanje primarnih i backup instanci servisa.
- Težinu (`weight = 10`): omogućava proporcionalnu raspodjelu opterećenja među servisima istog prioriteta.
- Port (`port = 6379`): eliminiše potrebu da klijenti hardkodiraju portove.
- Ciljni host (`target = cache.oblak.ruo.lab.`): kanonsko ime mašine koja pruža uslugu.

Klijentska aplikacija upitom za `_redis._tcp.oblak.ruo.lab` automatski saznaje i na kojoj adresi i na kojem portu se servis nalazi.

### 3. Idempotentnost i detekcija drifta
- **Prvo pokretanje:** Kreira se 6 resursa (4 A skupa zapisa, 1 CNAME, 1 TXT i 1 SRV).
- **Drugo pokretanje:** Terraform poređuje stanje u `terraform.tfstate` sa stvarnim stanjem na DNS serveru i javlja:
  ```text
  No changes. Your infrastructure matches the configuration.
  ```
- **Drift:** Ako vanjski proces (npr. administrator alatom `nsupdate` kroz `drift.sh`) obriše ili izmijeni zapis, Terraform `refresh` mehanizam detektuje odstupanje i `apply` automatski vraća definisano stanje iz koda.

---

## Pokretanje i provjera

### 1. Provjera plana i sintakse

```bash
make s5-p2
```
Izvršava `terraform init`, `validate` i `plan` sa dummy TSIG tajnom i `refresh=false`.

### 2. Potpuna primjena i testiranje u DNS labu

```bash
# 1. Podizanje DNS laba (BIND primarni + sekundarni u namespace-u)
make s5-dns

# 2. Primjena Terraform plana, provjera idempotentnosti i drift test
make s5-p2-apply
```

Izlaz drugog uzastopnog `apply` koraka potvrđuje očuvanu idempotentnost:
```text
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

Čišćenje:
```bash
make s5-p2-clean
```
