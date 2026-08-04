packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "agentlinux" {
  # Start from existing cloud image (not ISO)
  disk_image   = true
  iso_url      = var.debian_image_url
  iso_checksum = var.debian_image_checksum

  # VM specs
  cpus        = 2
  memory      = 2048
  disk_size   = "10G"
  accelerator = "kvm"
  headless    = true

  # Disk settings
  disk_interface = "virtio"
  net_device     = "virtio-net"
  format         = "qcow2"

  # Cloud-init via virtual CD (NoCloud datasource)
  cd_content = {
    "meta-data" = ""
    "user-data" = <<-EOF
      #cloud-config
      users:
        - name: packer
          plain_text_passwd: packer
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          lock_passwd: false
      ssh_pwauth: true
    EOF
  }
  cd_label = "cidata"

  # SSH for Packer provisioning
  ssh_username = "packer"
  ssh_password = "packer"
  ssh_timeout  = "5m"

  # Output
  output_directory = var.output_dir
  vm_name          = var.vm_name

  # Compact output
  disk_compression   = true
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  skip_compaction    = false

  # Packer user cleanup is handled by a oneshot systemd service on first boot
  # (see 06-cleanup.sh) since the user cannot be deleted while Packer's SSH
  # session is active.
  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
}

build {
  sources = ["source.qemu.agentlinux"]

  provisioner "shell" {
    execute_command  = "echo 'packer' | sudo -S bash -c '{{ .Vars }} {{ .Path }}'"
    environment_vars = ["ONE_CONTEXT_VERSION=${var.one_context_version}"]
    scripts = [
      "scripts/01-base.sh",
      "scripts/02-one-context.sh",
      "scripts/03-nodejs.sh",
      "scripts/04-chrome.sh",
      "scripts/05-agent-tools.sh",
      "scripts/06-cleanup.sh",
    ]
  }
}
