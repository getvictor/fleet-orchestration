#!/bin/bash

+set -Eeuo pipefail
+IFS=$'\n\t'

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/ansible-runtime"

echo "==================================="
echo "  Ansible Runtime Installer"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

if [ -z "$INSTALL_PATH" ]; then
    echo "Error: INSTALL_PATH environment variable is not set"
    echo "Usage: INSTALL_PATH=/path/to/temp/extract sudo ./install.sh"
    echo "Note: INSTALL_PATH should be the temporary directory where you extracted the tar.gz"
    exit 1
fi

if [ ! -d "${INSTALL_PATH}" ]; then
    echo "Error: ${INSTALL_PATH} does not exist"
    exit 1
fi

if [ ! -d "${INSTALL_PATH}/ansible-runtime" ]; then
    echo "Error: ansible-runtime directory not found at ${INSTALL_PATH}/ansible-runtime"
    echo "Please extract ansible-runtime.tar.gz to ${INSTALL_PATH} first:"
    echo "  tar -xzf ansible-runtime.tar.gz -C ${INSTALL_PATH}"
    exit 1
fi

echo "Checking system requirements..."

if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Installing minimal Python..."
    apt-get update
    apt-get install -y --no-install-recommends python3-minimal python3-pip python3-venv
else
    echo "✓ Python 3 is installed"
fi

if ! python3 -m pip --version &> /dev/null; then
    echo "pip is not installed. Installing..."
    apt-get install -y python3-pip
else
    echo "✓ pip is installed"
fi

if ! python3 -m venv --help &> /dev/null; then
    echo "venv module is not installed. Installing..."
    apt-get install -y python3-venv
else
    echo "✓ venv module is installed"
fi

echo ""
echo "Installing Ansible runtime from temporary location to ${PERMANENT_INSTALL_PATH}..."

# Check if permanent location already exists
if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Warning: ${PERMANENT_INSTALL_PATH} already exists - will be overwritten"
    rm -rf "${PERMANENT_INSTALL_PATH}"
fi

# Create permanent directory and copy files
echo "Copying files to permanent location..."
mkdir -p "$(dirname ${PERMANENT_INSTALL_PATH})"
cp -r "${INSTALL_PATH}/ansible-runtime" "${PERMANENT_INSTALL_PATH}"

echo "Setting up permissions..."
chmod -R 755 "${PERMANENT_INSTALL_PATH}"
chmod +x "${PERMANENT_INSTALL_PATH}/ansible/bin/"*

echo "Creating Python virtual environment..."
python3 -m venv "${PERMANENT_INSTALL_PATH}/venv"

echo "Installing Ansible in virtual environment..."
"${PERMANENT_INSTALL_PATH}/venv/bin/pip" install --upgrade pip
"${PERMANENT_INSTALL_PATH}/venv/bin/pip" install -r "${PERMANENT_INSTALL_PATH}/ansible/requirements.txt"

echo "Creating system-wide symlinks..."
ln -sf "${PERMANENT_INSTALL_PATH}/ansible/bin/ansible" /usr/local/bin/ansible
ln -sf "${PERMANENT_INSTALL_PATH}/ansible/bin/ansible-playbook" /usr/local/bin/ansible-playbook
ln -sf "${PERMANENT_INSTALL_PATH}/ansible/bin/ansible-galaxy" /usr/local/bin/ansible-galaxy

echo "Setting up Ansible environment..."
export ANSIBLE_CONFIG="${PERMANENT_INSTALL_PATH}/ansible/etc/ansible.cfg"
echo "export ANSIBLE_CONFIG=${PERMANENT_INSTALL_PATH}/ansible/etc/ansible.cfg" > /etc/profile.d/ansible.sh
chmod +x /etc/profile.d/ansible.sh

echo ""
echo "==================================="
echo "  Installation Complete!"
echo "==================================="
echo ""
echo "Ansible has been installed to: ${PERMANENT_INSTALL_PATH}"
echo "Configuration file: ${PERMANENT_INSTALL_PATH}/ansible/etc/ansible.cfg"
echo ""
echo "The temporary directory ${INSTALL_PATH} can now be safely deleted."
echo ""
echo "You can now run:"
echo "  - ansible --version"
echo "  - ansible-playbook --version"
echo ""
echo "To configure Apache, run: sudo ./post-install.sh"
echo ""
