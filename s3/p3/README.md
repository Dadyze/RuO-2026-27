# s3/p3: dvije mašine web1 i web2 pomoću for_each (Sedmica 3, zadatak 3)

**Zadatak:** u `s3/p3` napraviti dvije mašine pomoću `for_each` tako da inventory ima obje. Predati izlaz `terraform plan` bez izvršavanja `apply`.

## Šta je urađeno

- Varijabla `vm_name` zamijenjena je skupom `vms = ["web1", "web2"]`.
- Disk, cloud-init disk i domena imaju `for_each = var.vms`, a ime je `each.key`. Bazna slika je jedna i dijele je obje mašine.
- `inventory.ini` ima liniju `[web]` i po jednu liniju za svaku mašinu. Izlaz `ip` je mapa s adresama obje mašine.
- `make s3-p3-apply` prolazi kroz sve adrese, jer `terraform output -raw ip` radi samo za jednu vrijednost.

## Pokretanje (samo plan, bez apply)

```bash
make s3-p3
```

## Izlaz

```text
  # libvirt_cloudinit_disk.init["web1"] will be created
  # libvirt_cloudinit_disk.init["web2"] will be created
  # libvirt_domain.vm["web1"] will be created
  # libvirt_domain.vm["web2"] will be created
  # libvirt_volume.base will be created
  # libvirt_volume.disk["web1"] will be created
  # libvirt_volume.disk["web2"] will be created
  # local_file.inventory will be created

Plan: 8 to add, 0 to change, 0 to destroy.
```

Apply nije izvršen, pa sadržaj `inventory.ini` još nije vidljiv (adrese postoje tek kad se mašine pokrenu).
