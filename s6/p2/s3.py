#!/usr/bin/env python3
"""s6/p2: S3 klijent (boto3). Isti kod radi s AWS S3, Garage, Ceph RGW ili MinIO: mijenja se samo endpoint.

Pristup se čita iz okruženja (objekti.sh ga piše u s6/.lab/garage/s3.env):
  S3_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION

  s3.py demo BUCKET                 primjer korak po korak (put, ls, head, get, presigned URL, odbijen pristup)
  s3.py put  BUCKET KLJUČ DATOTEKA  upload
  s3.py get  BUCKET KLJUČ DATOTEKA  download
  s3.py ls   BUCKET [PREFIKS]       popis objekata
  s3.py rm   BUCKET KLJUČ           brisanje
"""
import hashlib
import os
import sys
import urllib.error
import urllib.request

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError


def klijent(kljuc=None, tajna=None):
    return boto3.client(
        "s3",
        endpoint_url=os.environ.get("S3_ENDPOINT", "http://127.0.0.1:3900"),
        region_name=os.environ.get("AWS_DEFAULT_REGION", "garage"),
        aws_access_key_id=kljuc or os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=tajna or os.environ.get("AWS_SECRET_ACCESS_KEY"),
        # path-style: http://host:3900/bucket/kljuc (bez DNS imena po bucketu)
        config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 2}),
    )


def korak(t):
    print(f"\n\033[1;36m== {t}\033[0m")


def ls(s3, bucket, prefiks=""):
    r = s3.list_objects_v2(Bucket=bucket, Prefix=prefiks)
    for o in r.get("Contents", []):
        print(f"  {o['LastModified']:%Y-%m-%d %H:%M:%S}  {o['Size']:>8} B  {o['Key']}")
    if not r.get("Contents"):
        print("  (prazno)")


def demo(bucket):
    s3 = klijent()

    korak("1. Bucketi kojima ovaj ključ ima pristup")
    for b in s3.list_buckets()["Buckets"]:
        print("  ", b["Name"])

    korak("2. PUT: objekat = ključ + bajtovi + metapodaci (nema direktorija ni djelimičnog pisanja)")
    tijelo = "narudzbe za novembar: 1001, 1002, 1003\n".encode()
    for k in ("izvjestaji/2026/11/novembar.txt", "izvjestaji/2026/10/oktobar.txt", "slike/logo.txt"):
        s3.put_object(Bucket=bucket, Key=k, Body=tijelo, ContentType="text/plain",
                      Metadata={"autor": "ruo", "sedmica": "6"})
        print(f"  PUT s3://{bucket}/{k}")

    korak("3. LIST s prefiksom: 'direktorij' je samo zajednički početak ključa")
    print(f"  prefiks 'izvjestaji/':")
    ls(s3, bucket, "izvjestaji/")
    r = s3.list_objects_v2(Bucket=bucket, Delimiter="/")
    print("  prvi nivo (Delimiter='/'):", [p["Prefix"] for p in r.get("CommonPrefixes", [])])

    korak("4. HEAD: metapodaci bez preuzimanja sadržaja; ETag je MD5 sadržaja (za obični PUT)")
    h = s3.head_object(Bucket=bucket, Key="izvjestaji/2026/11/novembar.txt")
    print(f"  ContentLength={h['ContentLength']}  ContentType={h['ContentType']}  Metadata={h['Metadata']}")
    print(f"  ETag={h['ETag']}   md5 lokalno=\"{hashlib.md5(tijelo).hexdigest()}\"")

    korak("5. Izmjena = novi PUT cijelog objekta (stari sadržaj se zamjenjuje, ne dopisuje)")
    s3.put_object(Bucket=bucket, Key="izvjestaji/2026/11/novembar.txt", Body=tijelo + b"1004\n")
    g = s3.get_object(Bucket=bucket, Key="izvjestaji/2026/11/novembar.txt")
    print("  GET:", g["Body"].read().decode().replace("\n", " | "))

    korak("6. Presigned URL: privremeni link bez ključa (vrijedi 60 s), npr. za preuzimanje iz browsera")
    url = s3.generate_presigned_url("get_object", Params={"Bucket": bucket, "Key": "slike/logo.txt"}, ExpiresIn=60)
    print("  ", url.split("?")[0] + "?X-Amz-...&X-Amz-Expires=60&X-Amz-Signature=...")
    with urllib.request.urlopen(url) as odg:
        print(f"   GET s potpisanim URL-om: HTTP {odg.status}")
    try:
        urllib.request.urlopen(url.split("?")[0])
    except urllib.error.HTTPError as e:
        print(f"   isti URL bez potpisa:      HTTP {e.code} (bucket nije javan)")

    korak("7. Pogrešan ključ: zahtjev je potpisan (AWS SigV4), pa server odbija nepoznat ključ")
    try:
        klijent("GK000000000000000000000000", "0" * 64).list_objects_v2(Bucket=bucket)
        print("   server je prihvatio nepoznat ključ (ne bi smio)")
    except ClientError as e:
        print(f"   {e.response['Error']['Code']}: {e.response['ResponseMetadata']['HTTPStatusCode']}")

    korak("8. Brisanje primjera (bucket ostaje za backup iz primjera 4)")
    for k in ("izvjestaji/2026/11/novembar.txt", "izvjestaji/2026/10/oktobar.txt", "slike/logo.txt"):
        s3.delete_object(Bucket=bucket, Key=k)
    ls(s3, bucket)


def main(a):
    if len(a) < 2:
        sys.exit(__doc__)
    cmd, bucket = a[0], a[1]
    s3 = klijent()
    if cmd == "demo":
        demo(bucket)
    elif cmd == "put" and len(a) == 4:
        s3.upload_file(a[3], bucket, a[2])
        print(f"  PUT s3://{bucket}/{a[2]}")
    elif cmd == "get" and len(a) == 4:
        s3.download_file(bucket, a[2], a[3])
    elif cmd == "ls":
        ls(s3, bucket, a[2] if len(a) > 2 else "")
    elif cmd == "rm" and len(a) == 3:
        s3.delete_object(Bucket=bucket, Key=a[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
