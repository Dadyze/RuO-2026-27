# s2/p3: dvije mašine web1 i web2 pomoću for_each (Sedmica 2, zadatak 2)

**Zadatak:** u `s2/p3` napraviti dvije mašine (`web1`, `web2`) pomoću `for_each` i dodati izlaz s obje adrese. Predati izlaz `terraform plan` (očekuje se `Plan: 7 to add`) bez izvršavanja `apply`.

## Šta je urađeno

- Varijabla `vm_name` zamijenjena je skupom `vms = ["web1", "web2"]`.
- Disk (`libvirt_volume.disk`), cloud-init disk (`libvirt_cloudinit_disk.init`) i domena (`libvirt_domain.vm`) imaju `for_each = var.vms`, a ime je `each.key`. Domena se na svoj disk i cloud-init poziva preko ključa (`libvirt_volume.disk[each.key].id`).
- Bazna slika (`libvirt_volume.base`) je jedna i dijele je obje mašine (`base_volume_id`).
- Izlaz `ip` je mapa s adresama obje mašine.

## Pokretanje (samo plan, bez apply)

```bash
make s2-p3
```

```text
  # libvirt_cloudinit_disk.init["web1"] will be created
  # libvirt_cloudinit_disk.init["web2"] will be created
  # libvirt_domain.vm["web1"] will be created
  # libvirt_domain.vm["web2"] will be created
  # libvirt_volume.base will be created
  # libvirt_volume.disk["web1"] will be created
  # libvirt_volume.disk["web2"] will be created

Plan: 7 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + ip = {
      + web1 = (known after apply)
      + web2 = (known after apply)
    }
```

7 resursa = 1 bazna slika + 2 diska + 2 cloud-init diska + 2 domene.

Čišćenje: `make s2-p3-clean`
