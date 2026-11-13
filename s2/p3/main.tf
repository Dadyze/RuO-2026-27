terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.3"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "vms" {
  type    = set(string)
  default = ["web1", "web2"]
}

# bazna slika se preuzima jednom, a disk VM-a je njen "copy-on-write" potomak
resource "libvirt_volume" "base" {
  name   = "ubuntu-noble-base.qcow2"
  pool   = "default"
  format = "qcow2"
  source = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

resource "libvirt_volume" "disk" {
  for_each       = var.vms
  name           = "${each.key}.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.base.id
  size           = 10 * 1024 * 1024 * 1024
}

resource "libvirt_cloudinit_disk" "init" {
  for_each = var.vms
  name     = "${each.key}-init.iso"
  pool     = "default"
  user_data = templatefile("${path.module}/cloud-init.tftpl", {
    hostname = each.key
    ssh_key  = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
  })
}

resource "libvirt_domain" "vm" {
  for_each  = var.vms
  name      = each.key
  memory    = 1024
  vcpu      = 1
  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  disk { volume_id = libvirt_volume.disk[each.key].id }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

# adrese obje mašine: { web1 = "...", web2 = "..." }
output "ip" {
  value = { for ime, vm in libvirt_domain.vm : ime => vm.network_interface[0].addresses[0] }
}
