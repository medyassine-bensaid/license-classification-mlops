0) Prep your Ubuntu VM (clean machine)
# 0.1 Update base OS
sudo apt-get update -y && sudo apt-get upgrade -y

# 0.2 Essentials
sudo apt-get install -y git curl jq unzip python3 python3-venv python3-pip build-essential

# 0.3 Terraform (HashiCorp apt repo)

sudo mkdir -p /etc/apt/keyrings

# Download and dearmor the GPG key
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg

# Add HashiCorp apt repo with signed-by
echo "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release; echo $UBUNTU_CODENAME) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

# Update and install Terraform
sudo apt-get update -y && sudo apt-get install -y terraform


# 0.4 kubectl (stable)
sudo apt-get install -y apt-transport-https ca-certificates gnupg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
sudo apt-get update -y && sudo apt-get install -y kubectl

# 0.5 Helm (v3)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 0.6 Ansible (plus Galaxy later)
sudo apt-get install -y ansible

# 0.7 OpenStack CLIs (client + magnum)
python3 -m pip install --upgrade pip
python3 -m pip install python-openstackclient python-magnumclient

1) Configure OpenStack auth (clouds.yaml)

Create ~/.config/openstack/clouds.yaml:

# ~/.config/openstack/clouds.yaml
clouds:
  my-openstack:
    auth:
      auth_url: https://OPENSTACK_IDENTITY:5000/v3
      username: YOUR_USERNAME
      password: YOUR_PASSWORD
      project_name: YOUR_PROJECT
      user_domain_name: Default
      project_domain_name: Default
    interface: public
    region_name: RegionOne


