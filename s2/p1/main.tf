terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "ime" {
  type    = string
  default = "RuO"
}

variable "imena" {
  type    = list(string)
  default = ["prva", "druga", "treca"]
}

resource "local_file" "pozdrav" {
  filename        = "${path.module}/pozdrav.txt"
  content         = "Zdravo, ${var.ime}!\n"
  file_permission = "0644"
}

# po jedna datoteka za svako ime iz liste; instance se prate po kljucu (imenu)
resource "local_file" "datoteke" {
  for_each        = toset(var.imena)
  filename        = "${path.module}/${each.key}.txt"
  content         = "Datoteka ${each.key}\n"
  file_permission = "0644"
}

output "putanja" {
  value = local_file.pozdrav.filename
}
