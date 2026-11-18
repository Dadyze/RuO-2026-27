# s4/p3: Proširenje vatrozida dozvolom porta 9090 i dopuna testne matrice (Sedmica 4, zadatak 3)

Ovaj primjer demonstrira mrežnu segmentaciju i stateful filtriranje saobraćaja pomoću Linux `nftables` alata na ruteru (`ruo-rtr`), uz verifikaciju matrice povezivosti kroz skriptu `test.sh`.

## Kontekst i zadatak

U troslojnoj arhitekturi (web / app / db), komponente su smještene u zasebne mrežne segmente:
- Web segment: `10.40.1.0/24`
- App segment: `10.40.2.0/24`
- Db segment: `10.40.3.0/24`

Zadatak za samostalni rad br. 3 zahtijeva:
1. U `firewall.nft` dodati pravilo koje dozvoljava saobraćaj sa `web` prema `app` na port 9090 (pored postojećeg porta 8080).
2. U `test.sh` dodati provjere za novu politiku: port 9090 mora biti dozvoljen, a port 9091 blokiran.
3. Objasniti zašto bez eksplicitnog pravila veza ne radi.

---

## Šta je urađeno

1. **`s4/p3/firewall.nft`**:
   - Definisan je imenovani skup aplikacijskih servisa `app_ports`:
     ```nftables
     set app_ports { type inet_service; elements = { 8080, 9090 } }
     ```
   - Pravilo u lancu `forward` prošireno je referenciranjem skupa `@app_ports`:
     ```nftables
     ip saddr $web ip daddr $app tcp dport @app_ports accept     # web -> app: aplikacijski portovi (8080, 9090)
     ```
2. **`s4/p3/test.sh`**:
   - Pokrenuti su TCP slušaoci unutar mrežnog prostora imena `ruo-app` na portovima 9090 i 9091:
     ```bash
     slusaj ruo-app 10.40.2.2 9090;  slusaj ruo-app 10.40.2.2 9091
     ```
   - Dodate su nove probe u matricu povezivosti:
     ```bash
     proba host 10.40.2.2 9090 blokirano    # internet -> app: direktan pristup blokiran
     proba web  10.40.2.2 9090 dozvoljeno   # web -> app (novi dozvoljeni port 9090)
     proba web  10.40.2.2 9091 blokirano    # web -> app (nedozvoljeni port 9091)
     ```

---

## Zašto bez pravila veza ne radi?

Lanac `forward` u tabeli `inet ruo` konfigurisan je sa podrazumijevanom politikom odbacivanja:

```nftables
chain forward {
    type filter hook forward priority filter; policy drop;
    ...
}
```

To implementira sigurnosni princip **najmanjih privilegija (default-deny / whitelist pristup)**:
1. Svi paketi koji prolaze kroz ruter između segmenata su automatski odbačeni (`drop`), osim ako eksplicitno ne odgovaraju nekom `accept` pravilu.
2. Kada klijent iz `web` segmenta pošalje inicijalni TCP SYN paket prema `app` na port 9090, paket stiže na ruter. Bez pravila koje dozvoljava taj odredišni port, paket ne pogađa nijedno pravilo u lancu `forward`, dostiže kraj lanca i primjenjuje se `policy drop`.
3. Budući da SYN paket nikada ne stigne do odredišta, veza ne može biti uspostavljena.
4. Pravilo `ct state established,related accept` na vrhu lanca propušta samo pakete koji pripadaju već uspješno uspostavljenim vezama. 
---

## Pokretanje i verifikacija

### 1. Provjera sintakse nftables datoteke (Dry-Run)

```bash
make s4-p3
```

Naredba izvršava `sudo nft -c -f s4/p3/firewall.nft`. Ako je sintaksa ispravna, ispisuje:
```text
firewall.nft je ispravan
```

### 2. Pokretanje i primjena u mrežnom labu

Ukoliko je podignut mrežni lab (`make s4-p2-up`), nova pravila i testna matrica se primjenjuju naredbom:

```bash
make s4-p3-apply
```

Očekivani ishod testne matrice prikazuje `ok` za sve probe, uključujući:
- `web    -> 10.40.2.2  :9090   dozvoljeno  (očekivano: dozvoljeno ) ok`
- `web    -> 10.40.2.2  :9091   blokirano   (očekivano: blokirano  ) ok`
- `host   -> 10.40.2.2  :9090   blokirano   (očekivano: blokirano  ) ok`

Čišćenje lab okruženja:
```bash
make s4-p2-clean
```
