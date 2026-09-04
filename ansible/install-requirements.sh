#!/bin/bash
# Install Ansible Galaxy requirements for pulp_container deployment playbooks

set -e

echo "========================================="
echo "Installing Ansible Galaxy Requirements"
echo "========================================="
echo ""

# Check if ansible-galaxy is available
if ! command -v ansible-galaxy &> /dev/null; then
    echo "ERROR: ansible-galaxy not found!"
    echo ""
    echo "Please install Ansible first:"
    echo "  pip3 install ansible"
    echo ""
    exit 1
fi

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install collections
echo "Installing collections from requirements.yml..."
ansible-galaxy collection install -r "${SCRIPT_DIR}/requirements.yml"

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""
echo "Installed collections:"
ansible-galaxy collection list | grep -E "community\.(postgresql|general)"
echo ""
echo "You can now run the deployment playbook:"
echo "  ansible-playbook -i inventory.yml deploy-optimization.yml"
echo ""
