packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "ubuntu" {
  iso_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  iso_checksum     = "file:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"
  disk_image       = true            # ulaz je gotov disk, ne instalacijski ISO
  format           = "qcow2"
  disk_size        = "10G"
  memory           = 1024
  accelerator      = "kvm"           # bez KVM-a: "tcg" (sporo)
  headless         = true
  cd_files         = ["./seed/user-data", "./seed/meta-data"]
  cd_label         = "cidata"
  ssh_username     = "ubuntu"
  ssh_password     = "packer"
  ssh_timeout      = "10m"
  shutdown_command = "sudo shutdown -P now"
  output_directory = "output"
  vm_name          = "ruo-base.qcow2"
}

build {
  sources = ["source.qemu.ubuntu"]

  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx qemu-guest-agent htop",
      "sudo systemctl enable nginx",
      "echo 'ruo-base 1.1' | sudo tee /etc/ruo-image-version",
      # čišćenje: build lozinka se zaključava, a cloud-init se resetuje da ponovo radi pri prvom pokretanju
      "sudo passwd -l ubuntu",
      "sudo cloud-init clean --logs --seed",
    ]
  }
}
