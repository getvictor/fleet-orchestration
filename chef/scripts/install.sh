#!/bin/bash

set -e

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/chef-runtime"

echo "==================================="
echo "  Chef Runtime Installer"
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

if [ ! -d "${INSTALLER_PATH}/chef-runtime" ]; then
    echo "Error: chef-runtime directory not found at ${INSTALLER_PATH}/chef-runtime"
    echo "Please extract chef-runtime.tar.gz to ${INSTALLER_PATH} first:"
    echo "  tar -xzf chef-runtime.tar.gz -C ${INSTALLER_PATH}"
    exit 1
fi

echo "Checking system requirements..."

# Check for required system libraries
REQUIRED_PACKAGES=""

if ! dpkg -l | grep -q libssl; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libssl3"
fi

if ! dpkg -l | grep -q libc6; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libc6"
fi

if ! dpkg -l | grep -q libgcc-s1; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libgcc-s1"
fi

if ! dpkg -l | grep -q libstdc++6; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libstdc++6"
fi

if [ ! -z "${REQUIRED_PACKAGES}" ]; then
    echo "Installing required system libraries..."
    apt-get update
    apt-get install -y ${REQUIRED_PACKAGES}
fi

echo "✓ System requirements satisfied"

echo ""
echo "Installing Chef runtime from temporary location to ${PERMANENT_INSTALL_PATH}..."

# Check if permanent location already exists
if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Warning: ${PERMANENT_INSTALL_PATH} already exists - will be overwritten"
    rm -rf "${PERMANENT_INSTALL_PATH}"
fi

# Create permanent directory and copy files
echo "Copying files to permanent location..."
mkdir -p "$(dirname ${PERMANENT_INSTALL_PATH})"
cp -r "${INSTALLER_PATH}/chef-runtime" "${PERMANENT_INSTALL_PATH}"

echo "Setting up permissions..."
chmod -R 755 "${PERMANENT_INSTALL_PATH}"
# Only chmod actual files, not symlinks
find "${PERMANENT_INSTALL_PATH}/chef/bin/" -type f -exec chmod +x {} \; 2>/dev/null || true
chmod +x "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/"*

# Create necessary directories for Chef
echo "Creating Chef working directories..."
mkdir -p /var/chef/cache
mkdir -p /var/chef/backup
mkdir -p /var/log/chef
chown -R root:root /var/chef
chmod -R 755 /var/chef

echo "Creating system-wide symlinks..."
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" /usr/local/bin/chef-client
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-solo" /usr/local/bin/chef-solo
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/knife" /usr/local/bin/knife
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin/chef-apply" /usr/local/bin/chef-apply

echo "Setting up Chef environment..."
cat > /etc/profile.d/chef.sh << EOF
# Chef Environment Configuration
export CHEF_HOME="${PERMANENT_INSTALL_PATH}"
export PATH="${PERMANENT_INSTALL_PATH}/chef/bin:\${PATH}"
EOF
chmod +x /etc/profile.d/chef.sh

# Verify the installation
echo ""
echo "Verifying Chef installation..."
export PATH="${PERMANENT_INSTALL_PATH}/chef/bin:${PATH}"

# Use the wrapper script for verification
if "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" --version >/dev/null 2>&1; then
    echo "✓ Chef Client is installed"
    "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" --version | head -n1
else
    echo "✗ Chef Client verification failed"
    # Try to debug the issue
    echo "Debug: Checking if Ruby exists..."
    ls -la "${PERMANENT_INSTALL_PATH}/chef/embedded/bin/ruby" 2>/dev/null || echo "Ruby not found"
    exit 1
fi

echo ""
echo "==================================="
echo "  Installation Complete!"
echo "==================================="
echo ""
echo "Chef has been installed to: ${PERMANENT_INSTALL_PATH}"
echo "Configuration file: ${PERMANENT_INSTALL_PATH}/chef/etc/client.rb"
echo "Cookbooks location: ${PERMANENT_INSTALL_PATH}/cookbooks"
echo ""
echo "The temporary directory ${INSTALLER_PATH} can now be safely deleted."
echo ""
echo "You can now run:"
echo "  - chef-client --version"
echo "  - chef-solo --version"
echo "  - knife --version"
