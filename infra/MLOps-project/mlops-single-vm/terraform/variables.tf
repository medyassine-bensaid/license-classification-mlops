variable "vm_ip" {
  description = "Public IP/DNS of the VM"
  type        = string
}

variable "vm_user" {
  description = "SSH username (e.g., ubuntu)"
  type        = string
}

variable "private_key_path" {
  description = "Path to SSH private key on local machine"
  type        = string
}

