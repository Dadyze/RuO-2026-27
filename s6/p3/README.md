# s6/p3: PostgreSQL migracije i ALTER DEFAULT PRIVILEGES (Sedmica 6, zadatak 4)

## Zadatak

Zadatak za samostalni rad br. 4 zahtijeva:
1. U `sql/` dodati novu migraciju `05-placanja.sql` s tabelom `prodaja.placanja`.
2. Bez izmjene `04-privilegije.sql` pokazati da uloga `app` u nju smije pisati.
3. Objasniti mehanizam koji to omogućava.
4. Predati i verifikovati otisak stanja nakon dvije primjene (dokaz idempotentnosti).

---

## Šta je urađeno

1. **Nova migracija `sql/05-placanja.sql`:**
   Kreirana je DDL skripta koja pod ulogom `vlasnik` kreira tabelu za evidenciju plaćanja povezanu sa narudžbama:
   ```sql
   \connect prodavnica
   SET client_min_messages = warning;
   SET ROLE vlasnik;

   CREATE TABLE IF NOT EXISTS prodaja.placanja (
     id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     narudzba_id bigint NOT NULL REFERENCES prodaja.narudzbe(id),
     iznos       numeric(10,2) NOT NULL CHECK (iznos > 0),
     metoda      text NOT NULL,
     vrijeme     timestamptz NOT NULL DEFAULT now()
   );

   RESET ROLE;
   ```

2. **Dopuna testova u `s6/p3/baza.sh`:**
   U funkciju `test_()` dodate su provjere:
   - `app: INSERT INTO placanja (default privilegije)` – provjera da `app` smije vršiti upis (očekivano: `DOZVOLJENO`)
   - `app: SELECT count(*) FROM placanja` – provjera čitanja (očekivano: `DOZVOLJENO`)
   - `app: DROP TABLE placanja` – provjera da `app` ne smije mijenjati strukturu niti brisati tabelu (očekivano: `ODBIJENO`)

---

## Zašto uloga `app` smije pisati bez izmjene `04-privilegije.sql`?

U standardnom radu sa PostgreSQL bazom, kada korisnik kreira novu tabelu, niko osim tog korisnika (i superusera) nema prava nad njom dok se eksplicitno ne izvrši `GRANT`. To bi značilo da svaka nova migracija mora ručno dodjeljivati prava, što je podložno greškama i zaboravljanju.

Rješenje ovog problema je mehanizam **`ALTER DEFAULT PRIVILEGES`** koji je već postavljen u skripti `04-privilegije.sql`:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE vlasnik IN SCHEMA prodaja GRANT SELECT, INSERT, UPDATE ON TABLES TO app;
```

### Mehanizam djelovanja:
1. **Prethodno definisano pravilo:** PostgreSQL pamti direktivu da za svaki novi objekat tipa `TABLE` koji uloga `vlasnik` ubuduće kreira unutar sheme `prodaja`, automatski dodijeli privilegije `SELECT`, `INSERT` i `UPDATE` ulozi `app`.
2. **Uloga kreatora (`SET ROLE vlasnik`):** U skripti `05-placanja.sql` ključna je naredba `SET ROLE vlasnik;`. Zahvaljujući njoj, PostgreSQL tabelu `prodaja.placanja` kreira u kontekstu uloge `vlasnik`, što odmah aktivira definisano pravilo zadanih privilegija.
3. **Princip najmanjih prava (Least Privilege):** Iako `app` odmah dobija prava pisanja i čitanja, uloga **nema** pravo `DELETE` (ne može brisati finansijsku evidenciju) niti `DROP TABLE` (jer nije vlasnik objekta), čime je postignuta maksimalna sigurnost podataka.

---

## Idempotentnost i otisak stanja (State Fingerprint)

Funkcija `primijeni()` u `baza.sh` koristi obrazac `sql/0*.sql` te automatski primjenjuje sve skripte abecednim redom (1 do 5).

Funkcija `otisak()` računa MD5 kontrolnu sumu globalnih uloga i definisane sheme (bez dinamičkih podataka i lozinki).

Budući da sve DDL naredbe koriste `IF NOT EXISTS` i deklarativni pristup, ponovno pokretanje migracija ne mijenja stanje baze: otisak nakon prve i nakon druge primjene ostaje identičan (npr. `a1b2c3d4e5f6`).

---

## Pokretanje i provjera

```bash
# 1. Podizanje baze, primjena migracija 2x i provjera otiska
make s6-p3

# 2. Pokretanje testne matrice privilegija
bash s6/p3/baza.sh test
```

### Očekivani izlaz testa za `placanja`:
```text
  app: INSERT INTO placanja (default privilegije)       DOZVOLJENO id=1
  app: SELECT count(*) FROM placanja                   DOZVOLJENO 1
  app: DROP TABLE placanja                             ODBIJENO   must be owner of table placanja
```

Čišćenje:
```bash
make s6-p3-clean
```
ili:
```bash
bash s6/p3/baza.sh down
```
