#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/puppet-runtime"

echo "==================================="
echo "  Puppet Runtime Installer"
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

if [ ! -d "${INSTALLER_PATH}/puppet-runtime" ]; then
    echo "Error: puppet-runtime directory not found at ${INSTALLER_PATH}/puppet-runtime"
    echo "Please extract puppet-runtime.tar.gz to ${INSTALLER_PATH} first:"
    echo "  tar -xzf puppet-runtime.tar.gz -C ${INSTALLER_PATH}"
    exit 1
fi

echo "Checking system requirements..."

# Detect Ubuntu version and architecture
if [ ! -f /etc/os-release ]; then
    echo "Error: /etc/os-release not found. This script requires Ubuntu 24.04."
    exit 1
fi

source /etc/os-release
if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "24.04" ]; then
    echo "Error: This script requires Ubuntu 24.04. Found: $ID $VERSION_ID"
    exit 1
fi

ARCH=$(dpkg --print-architecture)
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "arm64" ]; then
    echo "Error: This script requires AMD64 or ARM64 architecture. Found: $ARCH"
    exit 1
fi

echo "✓ Ubuntu 24.04 $ARCH detected"

# Ensure wget and gpg are available
if ! command -v wget &> /dev/null; then
    echo "Installing wget..."
    apt-get update
    apt-get install -y wget
fi

if ! command -v gpg &> /dev/null; then
    echo "Installing gnupg..."
    apt-get install -y gnupg
fi

echo ""
echo "Setting up Puppet repository..."

# Download and install Puppet repository
PUPPET_REPO_DEB="puppet-release-noble.deb"
PUPPET_REPO_URL="https://apt.puppet.com/${PUPPET_REPO_DEB}"

echo "Downloading Puppet repository package from ${PUPPET_REPO_URL}..."
wget -q -O "/tmp/${PUPPET_REPO_DEB}" "${PUPPET_REPO_URL}"

echo "Installing Puppet repository..."
dpkg -i "/tmp/${PUPPET_REPO_DEB}"
rm -f "/tmp/${PUPPET_REPO_DEB}"

echo "Updating package lists..."
apt-get update

echo "Installing Puppet agent..."
apt-get install -y puppet-agent

echo "✓ Puppet agent installed"

# Copy Puppet runtime files to permanent location
echo ""
echo "Installing Puppet runtime from temporary location to ${PERMANENT_INSTALL_PATH}..."

if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Warning: ${PERMANENT_INSTALL_PATH} already exists - will be overwritten"
    rm -rf "${PERMANENT_INSTALL_PATH}"
fi

echo "Copying files to permanent location..."
mkdir -p "$(dirname ${PERMANENT_INSTALL_PATH})"
cp -r "${INSTALLER_PATH}/puppet-runtime" "${PERMANENT_INSTALL_PATH}"

echo "Setting up permissions..."
chmod -R 755 "${PERMANENT_INSTALL_PATH}"
chmod +x "${PERMANENT_INSTALL_PATH}/puppet-apply-wrapper.sh"

# Create system-wide wrapper
echo "Creating system-wide puppet wrapper..."
cat > /usr/local/bin/puppet-apply << 'EOF'
#!/bin/bash
# Wrapper for Puppet apply with custom configuration
exec /opt/puppet-runtime/puppet-apply-wrapper.sh "$@"
EOF
chmod +x /usr/local/bin/puppet-apply

# Set up Puppet paths
echo "Setting up Puppet environment..."
if [ ! -f /etc/profile.d/puppet.sh ]; then
    cat > /etc/profile.d/puppet.sh << 'EOF'
# Puppet environment setup
export PATH="/opt/puppetlabs/puppet/bin:/usr/bin:$PATH"
export PUPPET_BASE="/opt/puppet-runtime"
EOF
    chmod +x /etc/profile.d/puppet.sh
fi

# Source the environment - check which path Puppet is installed in
if [ -f "/opt/puppetlabs/puppet/bin/puppet" ]; then
    export PATH="/opt/puppetlabs/puppet/bin:$PATH"
    PUPPET_BIN="/opt/puppetlabs/puppet/bin/puppet"
elif [ -f "/usr/bin/puppet" ]; then
    PUPPET_BIN="/usr/bin/puppet"
else
    PUPPET_BIN="puppet"
fi

echo ""
echo "==================================="
echo "  Installation Complete!"
echo "==================================="
echo ""
echo "Puppet has been installed to: ${PERMANENT_INSTALL_PATH}"
echo "Puppet agent version:"
$PUPPET_BIN --version || echo "Unable to determine version"
echo ""
echo "The temporary directory ${INSTALLER_PATH} can now be safely deleted."
echo ""
echo "You can now run:"
echo "  - puppet --version"
echo "  - puppet-apply (to apply local manifests)"
echo ""
echo "To configure Apache, run: sudo ./post-install.sh"
echo ""