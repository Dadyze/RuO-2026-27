# s2/p1: for_each nad listom imena (Sedmica 2, zadatak 1)

**Zadatak:** u `s2/p1` dodati drugu datoteku pomoću `for_each` nad listom imena i pratiti kako plan reaguje kad se element ukloni iz liste.

## Šta je urađeno

Dodana je varijabla `imena = ["prva", "druga", "treca"]` i resurs `local_file.datoteke` sa `for_each = toset(var.imena)`, koji pravi po jednu datoteku za svako ime (`prva.txt`, `druga.txt`, `treca.txt`). Generisane datoteke su dodane u `.gitignore`.

## Pokretanje

```bash
make s2-p1
```

Apply pravi 4 resursa (pozdrav i tri datoteke):

```text
Plan: 4 to add, 0 to change, 0 to destroy.
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

## Plan kada se iz liste ukloni "druga"

```bash
cd s2/p1 && terraform plan -var 'imena=["prva","treca"]'
```

```text
  # local_file.datoteke["druga"] will be destroyed
  # (because key ["druga"] is not in for_each map)

Plan: 0 to add, 0 to change, 1 to destroy.
```

Briše se samo `datoteke["druga"]`, a `prva` i `treca` ostaju netaknute, jer `for_each` prati instance po ključu (imenu), a ne po indeksu kao `count`. Sa `count` bi uklanjanje srednjeg elementa pomjerilo indekse, pa bi se mijenjale i ostale datoteke.

Čišćenje: `make s2-p1-clean`
