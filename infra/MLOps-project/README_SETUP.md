Quickflow after generation:
1) Edit mlops-single-vm/terraform/terraform.tfvars - set vm_ip, vm_user, private_key_path
2) Edit mlops-single-vm/ansible/inventory.ini - replace YOUR_VM_IP and /home/YOUR_LOCAL_USER/.ssh/id_rsa
3) Create a remote Git repo for mlops-manifests (or use an existing one) and obtain its HTTPS URL.
4) Edit mlops-manifests/apps/staging.yaml and apps/production.yaml, replace REPLACE_WITH_REPO_URL with your repo HTTPS URL.
5) Run setup_all.sh with env vars:
   VM_IP=your_vm_ip VM_USER=ubuntu PRIVATE_KEY=~/.ssh/id_rsa GITHUB_REPO=https://github.com/you/mlops-manifests.git ./setup_all.sh
