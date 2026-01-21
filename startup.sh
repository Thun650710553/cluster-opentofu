#!/bin/bash
# ==============================================================================
# Rancher RKE2 Node Registration Script (Enhanced for rancher.thunjp.space)
# ==============================================================================

exec > >(tee -a /var/log/rancher-join.log) 2>&1
set -x

echo "[START] Configuring Node for ${rancher_url}"

# 1. Fix Ubuntu 22.04 iptables (CRITICAL for RKE2)
# ------------------------------------------------------------------------------
echo "[INFO] Switching to iptables-legacy..."
update-alternatives --set iptables /usr/sbin/iptables-legacy || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true
update-alternatives --set arptables /usr/sbin/arptables-legacy || true
update-alternatives --set ebtables /usr/sbin/ebtables-legacy || true

# 2. Install Dependencies
# ------------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget ca-certificates gnupg lsb-release jq net-tools openssl

# 3. Trust the Self-Signed Certificate (The "Force Trust" Method)
# ------------------------------------------------------------------------------
echo "[INFO] Downloading Certificate from rancher.thunjp.space..."
# Extract host from URL (remove https://)
RANCHER_HOST=$(echo "${rancher_url}" | sed -e 's|^https\://||' -e 's|/.*$||')

# Download the cert directly from the server
openssl s_client -showcerts -connect $RANCHER_HOST:443 </dev/null 2>/dev/null | \
openssl x509 -outform PEM > /usr/local/share/ca-certificates/rancher-ca.crt

# Update OS trust store
update-ca-certificates

# 4. Configure Systemd to be "Insecure" (Double Safety)
# ------------------------------------------------------------------------------
# Even if cert trust fails, this tells the agent to ignore errors.
mkdir -p /etc/systemd/system/rancher-system-agent.service.d
cat <<EOF > /etc/systemd/system/rancher-system-agent.service.d/override.conf
[Service]
Environment="CATTLE_INSECURE=true"
EOF
systemctl daemon-reload

# 5. Execute Registration Command
# ------------------------------------------------------------------------------
echo "[INFO] Executing Join Command..."

# We set the variable just in case
export CATTLE_INSECURE=true

# Execute the command passed from Terraform
# This usually looks like: curl ... | sudo sh -s - ...
eval "${registration_command} ${node_roles}"

# 6. Monitor
# ------------------------------------------------------------------------------
echo "[INFO] Installation script finished. Monitoring log..."