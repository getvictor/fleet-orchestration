#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/ansible-runtime"

echo "==================================="
echo "  Sample Configuration via Ansible"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

# post-install.sh doesn't need INSTALL_PATH since Ansible is already installed
if [ ! -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Error: Ansible runtime not found at ${PERMANENT_INSTALL_PATH}"
    echo "Please run install.sh first"
    exit 1
fi

export ANSIBLE_CONFIG="${PERMANENT_INSTALL_PATH}/ansible/etc/ansible.cfg"
export PATH="${PERMANENT_INSTALL_PATH}/ansible/bin:${PATH}"

echo "Checking Ansible installation..."
if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible-playbook command not found"
    echo "Please ensure install.sh completed successfully"
    exit 1
fi

echo "Ansible version:"
ansible --version | head -n1
echo ""

PLAYBOOK_PATH="${PERMANENT_INSTALL_PATH}/playbooks/apache.yml"

if [ ! -f "${PLAYBOOK_PATH}" ]; then
    echo "Error: Apache playbook not found at ${PLAYBOOK_PATH}"
    exit 1
fi

echo "Running Apache installation playbook..."
echo "This will:"
echo "  - Install Apache2 web server"
echo "  - Configure it to serve a test page"
echo "  - Start the Apache service"

echo ""
echo "Executing Ansible playbook..."
echo "==================================="

cd "${PERMANENT_INSTALL_PATH}"

ansible-playbook "${PLAYBOOK_PATH}" \
    --connection=local \
    --inventory="localhost," \
    --extra-vars="var1=$FLEET_SECRET_VAR1 var2=var2_content" \
    -v

RESULT=$?

echo ""
echo "==================================="

if [ $RESULT -eq 0 ]; then
    echo "  Configuration Complete!"
    echo "==================================="
    echo ""
    echo "Apache has been successfully installed and configured!"
    echo ""

    echo "Apache Status: ✓ Running"

    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo ""
    echo "You can access the web server at:"
    echo "  - http://localhost/"
    if [ ! -z "$IP_ADDR" ]; then
        echo "  - http://${IP_ADDR}/"
    fi

    echo ""
    echo "To check Apache status: systemctl status apache2"
    echo "To view Apache logs: journalctl -u apache2"
else
    echo "  Configuration Failed!"
    echo "==================================="
    echo ""
    echo "The Ansible playbook encountered an error."
    echo "Please check the output above for details."
    exit 1
fi
