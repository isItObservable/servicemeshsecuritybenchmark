#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

sudo apt update
sudo apt install -y helm step sudo jq curl vim gpg ca-certificates
curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/smallstep.asc && \
    echo 'deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.asc] https://packages.smallstep.com/stable/debian debs main' \
    | tee /etc/apt/sources.list.d/smallstep.list
sudo apt-get update && apt-get -y install step-cli

sudo apt-get install  gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm



 echo "Installing kind..."
 curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
 chmod +x /tmp/kind
 sudo mv /tmp/kind /usr/local/bin/kind

 echo "Creating kind cluster with custom config..."
 kind create cluster --config .devcontainer/kind-cluster.yaml --wait 5m

 echo "Verifying cluster..."
 kubectl cluster-info
 kubectl get nodes

 echo "Kind cluster ready!"