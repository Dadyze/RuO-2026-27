# s5/p2: DNS zapisi kao Terraform resursi. Provider hashicorp/dns šalje izmjene na naš BIND
# protokolom RFC 2136 (dinamički UPDATE), potpisane TSIG ključem ruo-tf, koji smije mijenjati samo
# zonu oblak.ruo.lab. Isti obrazac vrijedi za DNS u oblaku (Route 53, Azure DNS, Cloudflare):
# mijenja se samo provider, a zapisi ostaju resursi s planom, stanjem i driftom.

terraform {
  required_version = ">= 1.5"
  required_providers {
    dns = { source = "hashicorp/dns", version = "~> 3.4" }
  }
}

variable "tsig_secret" {
  description = "TSIG tajna ključa ruo-tf (make je čita iz laba: s5/p1/dns.sh kljuc ruo-tf)"
  type        = string
  sensitive   = true
}

variable "zona" {
  type    = string
  default = "oblak.ruo.lab."
}

# servisi iz sedmice 4 (segmenti web/app/db) dobijaju imena; dvije adrese = dva A zapisa (round-robin)
variable "servisi" {
  type = map(list(string))
  default = {
    web = ["10.40.1.10", "10.40.1.11"]
    app = ["10.40.2.10"]
    db  = ["10.40.3.10"]
  }
}

provider "dns" {
  update {
    server        = "10.50.0.53"
    key_name      = "ruo-tf."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_secret
  }
}

resource "dns_a_record_set" "servis" {
  for_each  = var.servisi
  zone      = var.zona
  name      = each.key
  addresses = each.value
  ttl       = 300
}

resource "dns_cname_record" "www" {
  zone  = var.zona
  name  = "www"
  cname = "web.${var.zona}"
  ttl   = 300
}

resource "dns_txt_record_set" "vlasnik" {
  zone = var.zona
  txt  = ["upravlja: terraform (s5/p2)"]
  ttl  = 300
}

output "imena" {
  value = concat([for k, _ in dns_a_record_set.servis : "${k}.${var.zona}"], ["www.${var.zona}"])
}
