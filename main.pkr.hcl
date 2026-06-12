packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
    vagrant = {
      version = "~> 1"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

source "qemu" "ubuntu-cloud" {
  accelerator = "kvm"
  headless = true
  disk_image   = true

  iso_checksum = "file:https://cloud-images.ubuntu.com/noble/20260518/SHA256SUMS"
  iso_urls      = ["src-image/noble-server-cloudimg-amd64.img", "https://cloud-images.ubuntu.com/noble/20260518/noble-server-cloudimg-amd64.img"]
  iso_target_extension = "img"

  output_directory = "ubuntu-cloud-libvirt"

  shutdown_command = "sudo -n shutdown -P now"

  disk_size = "40960" #40GB

  communicator = "ssh"
  cd_content = {
    "meta-data" = ""
    "user-data"  = <<-EOF
      #cloud-config
      users:
        - name: ubuntu
          sudo: ALL=(ALL) NOPASSWD:ALL
          ssh_authorized_keys:
            - ${file("~/.ssh/id_rsa.pub")}
    EOF
  }
  cd_label         = "cidata"
  ssh_username     = "ubuntu"
  ssh_private_key_file = "~/.ssh/id_rsa"
  ssh_timeout      = "5m"
}

# ─── Build ───────────────────────────────────────────────────────────────────
build {
  sources = ["source.qemu.ubuntu-cloud"]

  provisioner "file" {
    source      = "files/99_vagrant.cfg"
    destination = "/tmp/99_vagrant.cfg"
  }

  provisioner "shell" {
    inline = ["sudo mv /tmp/99_vagrant.cfg /etc/cloud/cloud.cfg.d/99_vagrant.cfg"]
  }

  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs --machine-id",
      "sudo truncate -s 0 /etc/machine-id"
    ]
  }

  post-processor "vagrant" {
    vagrantfile_template = "Vagrantfile.template"
  }
}
