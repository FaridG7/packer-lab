# Ubuntu Cloud Box for libvirt

> Build a Vagrant-ready Ubuntu 24.04 (Noble Numbat) box for KVM/libvirt using HashiCorp Packer — fully automated, cloud-init configured, and SSH-hardened out of the box.

![Packer](https://img.shields.io/badge/Packer-02A8EF?style=flat&logo=packer&logoColor=white)
![Vagrant](https://img.shields.io/badge/Vagrant-1868F2?style=flat&logo=vagrant&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu_24.04-E95420?style=flat&logo=ubuntu&logoColor=white)
![KVM](https://img.shields.io/badge/KVM%2FQEMU-lightgrey?style=flat)

---

## Overview

This project was born out of a practical constraint: Vagrant Cloud was unreachable, making it impossible to pull the official `cloud-images/ubuntu-24.04` box. Rather than waiting, the solution was to build an equivalent box from scratch — using Ubuntu's own cloud images as the source and Packer to automate everything.

The result is functionally identical to the upstream box, but built and owned locally, and scoped specifically to the `libvirt` provider (KVM/QEMU). It starts from the official Ubuntu 24.04 cloud image and produces a reproducible, minimal box with:

- **Vagrant user** provisioned via cloud-init (SSH key auth, passwordless sudo/doas)
- **Password authentication disabled** — SSH key access only
- **Clean machine-id** and cloud-init state for proper re-initialization on first boot
- **40 GB virtual disk** with KVM acceleration

The build pipeline is defined entirely as code — no manual VM setup involved.

---

## How It Works

```
Ubuntu 24.04 Cloud Image
        │
        ▼
  Packer (QEMU plugin)
  ┌─────────────────────────────┐
  │  1. Boot VM via KVM/QEMU   │
  │  2. Inject cloud-init cfg  │  ← cidata ISO (NoCloud datasource)
  │  3. Provision Vagrant user │  ← files/99_vagrant.cfg
  │  4. Clean cloud-init state │
  └─────────────────────────────┘
        │
        ▼
  Vagrant Post-Processor
        │
        ▼
   .box artifact  ←── ready for `vagrant box add`
```

Packer boots the cloud image using QEMU with KVM acceleration. A temporary cloud-init ISO (using the `NoCloud` datasource) injects SSH credentials so Packer can connect and provision the machine. A second cloud-init config (`99_vagrant.cfg`) is then dropped into `/etc/cloud/cloud.cfg.d/` to configure the Vagrant user for all future boots. Finally, cloud-init state and the machine ID are wiped so the box initializes cleanly every time it is instantiated.

---

## Project Structure

```
.
├── main.pkr.hcl          # Packer build definition (source + build blocks)
├── Vagrantfile.template  # Embedded in the .box; used by Vagrant on `vagrant up`
└── files/
    └── 99_vagrant.cfg    # cloud-init drop-in: Vagrant user, SSH keys, sudo/doas
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| [Packer](https://developer.hashicorp.com/packer/install) | ≥ 1.9 | HashiCorp IaC image builder |
| [QEMU](https://www.qemu.org/) | any recent | `qemu-system-x86_64` must be on `$PATH` |
| KVM | — | Kernel module; check with `lsmod \| grep kvm` |
| [Vagrant](https://developer.hashicorp.com/vagrant/install) | ≥ 2.3 | For consuming the built box |
| [vagrant-libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt) | ≥ 0.12 | Vagrant provider plugin for libvirt |
| libvirt / virtd | — | Running daemon (`systemctl status libvirtd`) |

Your user must have access to `/dev/kvm`. Add yourself to the `kvm` group if needed:

```bash
sudo usermod -aG kvm $USER
```

---

## Usage

### 1. Initialize Packer plugins

```bash
packer init main.pkr.hcl
```

### 2. (Optional) Download the base image in advance

Packer will download the Ubuntu cloud image automatically if it is not found locally. To pre-cache it:

```bash
mkdir -p src-image
wget -O src-image/noble-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/noble/20260518/noble-server-cloudimg-amd64.img
```

### 3. Build the box

```bash
packer build main.pkr.hcl
```

The build will:
1. Verify the image checksum against Ubuntu's `SHA256SUMS`
2. Boot the VM and provision it over SSH
3. Output a `.box` file via the Vagrant post-processor

### 4. Add the box to Vagrant

```bash
vagrant box add ubuntu-24.04-libvirt ubuntu-cloud-libvirt/package.box
```

### 5. Use it in a Vagrantfile

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu-24.04-libvirt"

  config.vm.provider :libvirt do |libvirt|
    libvirt.driver = "kvm"
    libvirt.uri    = "qemu:///system"
  end
end
```

---

## Key Configuration Details

### SSH Hardening (`files/99_vagrant.cfg`)

Password authentication is explicitly disabled at the cloud-init level:

```yaml
ssh_pwauth: False
```

The Vagrant insecure public key is pre-authorized to match the Vagrant workflow, and a `vagrant` user is created with full passwordless sudo and doas access — mirroring the convention expected by Vagrant's SSH subsystem.

### Clean Machine Identity

Before the box is packaged, cloud-init state and the machine ID are wiped:

```bash
sudo cloud-init clean --logs --machine-id
sudo truncate -s 0 /etc/machine-id
```

This ensures every VM instance spun up from the box gets a fresh identity and cloud-init re-runs on first boot — critical for producing non-conflicting VMs on the same host.

### Vagrantfile Template

The embedded `Vagrantfile.template` disables the default `/vagrant` synced folder (improving isolation) and wires up cloud-init support so consumers can inject per-instance configuration without re-building the box.

---

## Concepts Explored

This project was built as a hands-on exploration of the following topics:

- **Infrastructure as Code** — defining VM images declaratively with HCL
- **Packer build pipeline** — sources, provisioners, and post-processors
- **KVM/QEMU virtualization** — hardware-accelerated VMs on Linux
- **cloud-init** — automated Linux instance initialization (datasources, user-data, drop-in configs)
- **Vagrant box internals** — box format, embedded Vagrantfiles, and provider metadata
- **SSH hardening** — key-only auth, user provisioning without passwords
- **Reproducible builds** — checksum verification, clean machine state

---

## Troubleshooting

**Build hangs at SSH connection**
Confirm KVM is available (`ls /dev/kvm`) and your user is in the `kvm` group. Without hardware acceleration the VM may be too slow to boot within the SSH timeout.

**`qemu: not found`**
Install QEMU: `sudo apt install qemu-system-x86_64` (Debian/Ubuntu) or equivalent.

**Checksum mismatch**
The `iso_checksum` URL points to a specific dated snapshot. If that snapshot is no longer hosted, update the date in `iso_urls` and `iso_checksum` to a current one from [cloud-images.ubuntu.com/noble](https://cloud-images.ubuntu.com/noble/).

---

## License

This project is released under the [MIT License](LICENSE).
