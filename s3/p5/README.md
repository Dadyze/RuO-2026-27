# s3/p5: brojač (web + Redis) kao Kubernetes manifest (Sedmica 3, zadatak 5)

**Zadatak:** isti sistem iz primjera 4 (`s3/p4`, web brojač + Redis) napisati kao Kubernetes manifest (Deployment + Service za `web` i `redis`); sliku učitati u kind pomoću `kind load docker-image`.

Originalni primjer s nginxom (`web.yaml`, `make s3-p5`) ostaje nepromijenjen. Rješenje je u `brojac.yaml`.

## Šta je urađeno

Sve je u namespace-u `brojac`, da se ne miješa s primjerom `web.yaml` (oba imaju Deployment i Service `web`).

| compose.yaml (s3/p4) | brojac.yaml (Kubernetes) |
|---|---|
| servis `redis` (`redis:7-alpine`, `--appendonly yes`) | Deployment `redis` + Service `redis` (port 6379) |
| volumen `redisdata` | PersistentVolumeClaim `redisdata` (1Gi), montiran na `/data` |
| healthcheck `redis-cli ping` | `readinessProbe` sa `redis-cli ping` |
| servis `web` (`ruo/brojac:1.0`, `REDIS_HOST=redis`) | Deployment `web` (2 replike) + Service `web` (port 80 → 8000) |
| `ports: 8080:8000` | `kubectl port-forward svc/web 8082:80` |
| mreža `backend` (Redis nije objavljen) | Service `redis` je ClusterIP, dostupan samo unutar klastera |

- Ime Servisa `redis` je DNS ime unutar namespace-a, pa web nalazi Redis preko `REDIS_HOST=redis`, isto kao u Composeu.
- Slika `ruo/brojac:1.0` se gradi lokalno iz `s3/p4/app` i učitava u kind čvor sa `kind load docker-image ruo/brojac:1.0 --name ruo`. Zato web ima `imagePullPolicy: IfNotPresent`: slika nije na registru i ne smije se povlačiti.
- `livenessProbe` je `/health` (proces radi), a `readinessProbe` je `/ready` (Redis je dostupan). Kad Redis padne, `/ready` vraća 503, pa se Pod privremeno skloni iz Servisa, ali se ne restartuje, jer `/health` i dalje vraća 200.
- Obje web replike koriste isti Redis, pa brojač raste bez obzira na to koji Pod odgovori.

## Pokretanje

```bash
make s3-p5-r          # dry-run manifesta
make s3-p5-r-up       # kind klaster, docker build, kind load, apply, 3 posjete
make s3-p5-r-clean    # briše namespace brojac
make s3-p5-clean      # briše cijeli kind klaster
```

`make s3-p5-r-up` redom:

1. pravi kind klaster `ruo` (ako ne postoji),
2. gradi sliku `ruo/brojac:1.0` iz `s3/p4/app`,
3. učitava je u kind (`kind load docker-image`),
4. primjenjuje `brojac.yaml` i čeka da `redis` i `web` budu spremni,
5. ispisuje Podove, Servise i PVC, pa šalje 3 zahtjeva preko Servisa `web` (brojač raste: Posjeta broj 1, 2, 3).

## Rezultat (`make s3-p5-r-up`)

```text
deployment "web" successfully rolled out
kubectl -n brojac get pods,svc,pvc -o wide
NAME                         READY   STATUS    RESTARTS   AGE   IP           NODE
pod/redis-7d668ddb87-jtv4l   1/1     Running   0          36s   10.244.0.8   ruo-control-plane
pod/web-6945bc7fcd-95mft     1/1     Running   0          36s   10.244.0.4   ruo-control-plane
pod/web-6945bc7fcd-h858p     1/1     Running   0          36s   10.244.0.5   ruo-control-plane

NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE   SELECTOR
service/redis   ClusterIP   10.96.90.8     <none>        6379/TCP   36s   app=redis
service/web     ClusterIP   10.96.159.84   <none>        80/TCP     36s   app=web

NAME                              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/redisdata   Bound    pvc-3bc2a53b-361a-477a-97d9-16216374e8ed   1Gi        RWO            standard

== 3 zahtjeva preko Servisa web: brojac raste
Posjeta broj 1
Posjeta broj 2
Posjeta broj 3
```

Jedan Pod za Redis i dvije web replike rade (`1/1 Running`), oba Servisa su ClusterIP, a PVC je vezan (`Bound`) na zadanu `standard` klasu pohrane u kindu. Brojač raste preko Servisa `web`, iako zahtjeve dijele dvije replike, jer obje koriste isti Redis.
