variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "debian_image_checksum" {
  type    = string
  default = "file:https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"
}

variable "one_context_version" {
  type    = string
  default = "6.10.0-3"
}

variable "output_dir" {
  type    = string
  default = "../output"
}

variable "vm_name" {
  type    = string
  default = "agentlinux-0.2.0-amd64.qcow2"
}
