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

# Check for bundled .deb files
PUPPET_AGENT_DEB="${INSTALLER_PATH}/puppet-runtime/puppet-agent.deb"
PUPPET_RELEASE_DEB="${INSTALLER_PATH}/puppet-runtime/puppet-release-noble.deb"

if [ ! -f "$PUPPET_AGENT_DEB" ]; then
    echo "Error: puppet-agent.deb not found at $PUPPET_AGENT_DEB"
    exit 1
fi

if [ ! -f "$PUPPET_RELEASE_DEB" ]; then
    echo "Error: puppet-release-noble.deb not found at $PUPPET_RELEASE_DEB"
    exit 1
fi

echo ""
echo "Installing Puppet from bundled packages..."

# Install the Puppet release package first (sets up repository configuration)
echo "Installing Puppet release configuration..."
dpkg -i "$PUPPET_RELEASE_DEB" || {
    echo "Error: Failed to install Puppet release package"
    exit 1
}

# Install the Puppet agent package
echo "Installing Puppet agent..."
dpkg -i "$PUPPET_AGENT_DEB" 2>/dev/null || {
    # If dpkg fails due to dependencies, try to fix them
    echo "Fixing dependencies..."
    apt-get update
    apt-get install -f -y || {
        echo "Error: Failed to install Puppet agent dependencies"
        exit 1
    }
    
    # Try installing again
    dpkg -i "$PUPPET_AGENT_DEB" || {
        echo "Error: Failed to install Puppet agent package"
        exit 1
    }
}

echo "✓ Puppet agent installed"

# Verify Puppet installation
if [ ! -d "/opt/puppetlabs" ]; then
    echo "Error: /opt/puppetlabs directory was not created after installation"
    exit 1
fi

if [ ! -f "/opt/puppetlabs/puppet/bin/puppet" ]; then
    echo "Error: Puppet binary not found at /opt/puppetlabs/puppet/bin/puppet"
    exit 1
fi

# Copy Puppet runtime configuration to permanent location
echo ""
echo "Installing custom Puppet configuration to ${PERMANENT_INSTALL_PATH}..."

if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Warning: ${PERMANENT_INSTALL_PATH} already exists - will be overwritten"
    rm -rf "${PERMANENT_INSTALL_PATH}"
fi

echo "Copying configuration files..."
mkdir -p "${PERMANENT_INSTALL_PATH}"

# Copy our custom configuration, modules, and manifests
for dir in config modules manifests; do
    if [ -d "${INSTALLER_PATH}/puppet-runtime/$dir" ]; then
        cp -r "${INSTALLER_PATH}/puppet-runtime/$dir" "${PERMANENT_INSTALL_PATH}/"
        echo "✓ Copied $dir"
    fi
done

# Copy wrapper scripts
if [ -f "${INSTALLER_PATH}/puppet-runtime/puppet-apply-wrapper.sh" ]; then
    cp "${INSTALLER_PATH}/puppet-runtime/puppet-apply-wrapper.sh" "${PERMANENT_INSTALL_PATH}/"
    chmod +x "${PERMANENT_INSTALL_PATH}/puppet-apply-wrapper.sh"
fi

echo "Setting up permissions..."
chmod -R 755 "${PERMANENT_INSTALL_PATH}"

# Create system-wide wrapper for puppet-apply
echo "Creating system-wide puppet-apply wrapper..."
cat > /usr/local/bin/puppet-apply << 'EOF'
#!/bin/bash
# Wrapper for Puppet apply with custom configuration
exec /opt/puppet-runtime/puppet-apply-wrapper.sh "$@"
EOF
chmod +x /usr/local/bin/puppet-apply

# Create symlinks for Puppet commands
echo "Creating command symlinks..."
ln -sf /opt/puppetlabs/puppet/bin/puppet /usr/local/bin/puppet
ln -sf /opt/puppetlabs/puppet/bin/facter /usr/local/bin/facter
ln -sf /opt/puppetlabs/puppet/bin/hiera /usr/local/bin/hiera

# Set up Puppet paths
echo "Setting up Puppet environment..."
if [ ! -f /etc/profile.d/puppet.sh ]; then
    cat > /etc/profile.d/puppet.sh << 'EOF'
# Puppet environment setup
export PATH="/opt/puppetlabs/puppet/bin:/usr/local/bin:$PATH"
export PUPPET_BASE="/opt/puppet-runtime"
EOF
    chmod +x /etc/profile.d/puppet.sh
fi

# Export for current session
export PATH="/opt/puppetlabs/puppet/bin:/usr/local/bin:$PATH"

echo ""
echo "==================================="
echo "  Installation Complete!"
echo "==================================="
echo ""
echo "Puppet has been installed to: /opt/puppetlabs"
echo "Custom configuration installed to: ${PERMANENT_INSTALL_PATH}"
echo ""
echo "Puppet agent version:"
/opt/puppetlabs/puppet/bin/puppet --version || echo "Unable to determine version"
echo ""
echo "The temporary directory ${INSTALLER_PATH} can now be safely deleted."
echo ""
echo "You can now run:"
echo "  - puppet --version"
echo "  - puppet-apply (to apply local manifests)"
echo ""
echo "To configure Apache, run: sudo ./post-install.sh"
echo ""