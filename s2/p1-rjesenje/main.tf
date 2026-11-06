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
  default = ["file_1", "file_2", "file_3"]
}

# docs: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
resource "local_file" "file" {
  for_each        = toset(var.imena)
  filename        = "${path.module}/${each.key}.txt"
  content         = "Kreiran: ${each.key}!\n"
  file_permission = "0644"
}
resource "local_file" "pozdrav" {
  filename        = "${path.module}/pozdrav.txt"
  content         = "Zdravo, ${var.ime}!\n"
  file_permission = "0644"
}

output "putanja" {
  value = local_file.pozdrav.filename
}
