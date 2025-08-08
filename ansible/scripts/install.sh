#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

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

if [ -z "$INSTALLER_PATH" ]; then
    echo "Error: INSTALLER_PATH environment variable is not set"
    echo "Usage: INSTALLER_PATH=/path/to/temp/extract sudo ./install.sh"
    echo "Note: INSTALLER_PATH should be the temporary directory where you extracted the tar.gz"
    exit 1
fi

if [ ! -d "${INSTALLER_PATH}" ]; then
    echo "Error: ${INSTALLER_PATH} does not exist"
    exit 1
fi

if [ ! -d "${INSTALLER_PATH}/ansible-runtime" ]; then
    echo "Error: ansible-runtime directory not found at ${INSTALLER_PATH}/ansible-runtime"
    echo "Please extract ansible-runtime.tar.gz to ${INSTALLER_PATH} first:"
    echo "  tar -xzf ansible-runtime.tar.gz -C ${INSTALLER_PATH}"
    exit 1
fi

echo "Checking system requirements..."

# Detect Python version
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Installing minimal Python..."
    apt-get update
    apt-get install -y --no-install-recommends python3-minimal python3-pip python3-venv wget
else
    echo "✓ Python 3 is installed"
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
    echo "  Python version: $PYTHON_VERSION"
fi

# Ensure wget is available (needed for fallback pip installation)
if ! command -v wget &> /dev/null; then
    echo "Installing wget..."
    apt-get update
    apt-get install -y wget
fi

if ! python3 -m pip --version &> /dev/null; then
    echo "pip is not installed. Installing..."
    apt-get install -y python3-pip
else
    echo "✓ pip is installed"
fi

# Check and install venv with version-specific package if needed
if ! python3 -m venv --help &> /dev/null 2>&1; then
    echo "venv module is not installed. Installing..."
    
    # Try to determine the specific Python version for venv package
    PYTHON_MAJOR_MINOR=$(python3 --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    # First try the version-specific package
    if [ -n "$PYTHON_MAJOR_MINOR" ]; then
        echo "Attempting to install python${PYTHON_MAJOR_MINOR}-venv..."
        if apt-get install -y python${PYTHON_MAJOR_MINOR}-venv 2>/dev/null; then
            echo "✓ Installed python${PYTHON_MAJOR_MINOR}-venv"
        else
            # Fallback to generic package
            echo "Version-specific package not found, trying generic python3-venv..."
            apt-get install -y python3-venv
        fi
    else
        # Fallback to generic package
        apt-get install -y python3-venv
    fi
else
    echo "✓ venv module is installed"
fi

# Verify venv is really working
echo "Verifying Python venv functionality..."
if python3 -m venv --help &> /dev/null 2>&1; then
    echo "✓ Python venv is functional"
else
    echo "Error: Python venv still not working after installation"
    echo "You may need to manually install: apt-get install python$(python3 --version | grep -oE '[0-9]+\.[0-9]+' | head -1)-venv"
    exit 1
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
cp -r "${INSTALLER_PATH}/ansible-runtime" "${PERMANENT_INSTALL_PATH}"

echo "Setting up permissions..."
chmod -R 755 "${PERMANENT_INSTALL_PATH}"
chmod +x "${PERMANENT_INSTALL_PATH}/ansible/bin/"*

echo "Creating Python virtual environment..."
if ! python3 -m venv "${PERMANENT_INSTALL_PATH}/venv"; then
    echo "Error: Failed to create virtual environment"
    echo "This might be due to missing ensurepip module"
    echo ""
    echo "Trying alternative method with --without-pip flag..."
    if python3 -m venv --without-pip "${PERMANENT_INSTALL_PATH}/venv"; then
        echo "Virtual environment created without pip, installing pip manually..."
        # Download and install pip manually
        wget -q -O /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
        "${PERMANENT_INSTALL_PATH}/venv/bin/python3" /tmp/get-pip.py
        rm -f /tmp/get-pip.py
    else
        echo "Error: Could not create virtual environment"
        echo "Please check Python installation and try again"
        exit 1
    fi
fi

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
echo "The temporary directory ${INSTALLER_PATH} can now be safely deleted."
echo ""
echo "You can now run:"
echo "  - ansible --version"
echo "  - ansible-playbook --version"
echo ""
echo "To configure Apache, run: sudo ./post-install.sh"
echo ""
