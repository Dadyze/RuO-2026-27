# s2/p1-rjesenje

Za kreiranje fajlova:

```text
$ tf plan -no-color
Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.file["file_1"] will be created
  + resource "local_file" "file" {
      + content              = <<-EOT
            Kreiran: file_1!
        EOT
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0644"
      + filename             = "./file_1.txt"
      + id                   = (known after apply)
    }

  # local_file.file["file_2"] will be created
  + resource "local_file" "file" {
      + content              = <<-EOT
            Kreiran: file_2!
        EOT
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0644"
      + filename             = "./file_2.txt"
      + id                   = (known after apply)
    }

  # local_file.file["file_3"] will be created
  + resource "local_file" "file" {
      + content              = <<-EOT
            Kreiran: file_3!
        EOT
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0644"
      + filename             = "./file_3.txt"
      + id                   = (known after apply)
    }

  # local_file.pozdrav will be created
  + resource "local_file" "pozdrav" {
      + content              = <<-EOT
            Zdravo, RuO!
        EOT
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0644"
      + filename             = "./pozdrav.txt"
      + id                   = (known after apply)
    }

Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + putanja = "./pozdrav.txt"

─────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
$ tf apply
$ /RuO-2026-27/s2/p1-rjesenje$ ls
file_1.txt  file_2.txt  file_3.txt  main.tf  pozdrav.txt  terraform.tfstate
$ tf plan -no-color  # nakon brisanje "file_2" iz liste:
local_file.pozdrav: Refreshing state... [id=055750614a08eb481920ebb12964527f022f7a8d]
local_file.file["file_2"]: Refreshing state... [id=a58d46583b82bff1cb122faff0d8604d6be85c5c]
local_file.file["file_1"]: Refreshing state... [id=8981600ce09b6feeee071cfaedf03f5c36c6b580]
local_file.file["file_3"]: Refreshing state... [id=68f6993e5ebb1727523be670d19d8d78d1310fe7]

Terraform used the selected providers to generate the following execution plan. Resource actions
are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # local_file.file["file_2"] will be destroyed
  # (because key ["file_2"] is not in for_each map)
  - resource "local_file" "file" {
      - content              = <<-EOT
            Kreiran: file_2!
        EOT -> null
      - content_base64sha256 = "QaRvytWvlMndyXO8nwL1xc6EHVt1cHtfUxqSARjBEdI=" -> null
      - content_base64sha512 = "lzs6nbm3x7Vi2PXv+ywpJ1qo/gXglYcolhFFbF9Q7JDPtYB7h2PPXWuiBaUQ1HapzknCVHDDNfnH3d9DHPtwqQ==" -> null
      - content_md5          = "3c31dd02a2439a0a3a5b09b7a55a44a3" -> null
      - content_sha1         = "a58d46583b82bff1cb122faff0d8604d6be85c5c" -> null
      - content_sha256       = "41a46fcad5af94c9ddc973bc9f02f5c5ce841d5b75707b5f531a920118c111d2" -> null
      - content_sha512       = "973b3a9db9b7c7b562d8f5effb2c29275aa8fe05e09587289611456c5f50ec90cfb5807b8763cf5d6ba205a510d476a9ce49c25470c335f9c7dddf431cfb70a9" -> null
      - directory_permission = "0777" -> null
      - file_permission      = "0644" -> null
      - filename             = "./file_2.txt" -> null
      - id                   = "a58d46583b82bff1cb122faff0d8604d6be85c5c" -> null
    }

Plan: 0 to add, 0 to change, 1 to destroy.

───────────────────────────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't guarantee to take
exactly these actions if you run "terraform apply" now.
```
