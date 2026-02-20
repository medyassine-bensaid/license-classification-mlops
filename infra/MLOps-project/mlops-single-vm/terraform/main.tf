# Terraform is used only to run local "provisioner-like" actions via a null_resource.
# For this local-VM flow the file is mostly a placeholder that the later script uses.
terraform {
  required_version = ">= 1.6.0"
}
resource "null_resource" "vm_preparer" {
  triggers = {
    vm_ip = var.vm_ip
    user  = var.vm_user
  }
}

