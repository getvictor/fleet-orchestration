#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUILD_DIR="${OUTPUT_DIR}/build"
PUPPET_VERSION="8"  # Puppet 8 is the latest stable

# Detect architecture
ARCH="amd64"  # Default to amd64
if [[ $(uname -m) == "arm64" ]] || [[ $(uname -m) == "aarch64" ]]; then
    ARCH="arm64"
fi

echo "=== Puppet Runtime Builder ==="
echo "Building for: Ubuntu 24.04 ($ARCH)"
echo ""

rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}/puppet-runtime"

echo "Step 1: Downloading Puppet release package..."
cd "${BUILD_DIR}"

# Download the Puppet release package for Ubuntu 24.04 (Noble)
wget -q https://apt.puppet.com/puppet-release-noble.deb || {
    echo "Error: Failed to download Puppet release package"
    exit 1
}

echo "Step 2: Extracting package information..."
# We'll download the packages directly without extracting on macOS

echo "Step 3: Downloading Puppet agent package..."
# Get the repository URL and key from the extracted files
REPO_URL="https://apt.puppet.com"
DIST="noble"
COMPONENT="puppet${PUPPET_VERSION}"

# Download the Packages file to find the puppet-agent package
mkdir -p tmp
wget -q "${REPO_URL}/dists/${DIST}/${COMPONENT}/binary-${ARCH}/Packages.gz" -O tmp/Packages.gz || {
    echo "Error: Failed to download package list for ${ARCH}"
    exit 1
}
gunzip tmp/Packages.gz

# Find the puppet-agent package filename
PUPPET_AGENT_PACKAGE=$(grep "^Filename:.*puppet-agent" tmp/Packages | head -1 | awk '{print $2}')
if [ -z "$PUPPET_AGENT_PACKAGE" ]; then
    echo "Error: Could not find puppet-agent package in repository"
    exit 1
fi

echo "Found puppet-agent package: $PUPPET_AGENT_PACKAGE"

# Download the actual puppet-agent .deb package
wget -q "${REPO_URL}/${PUPPET_AGENT_PACKAGE}" -O puppet-agent.deb || {
    echo "Error: Failed to download puppet-agent package"
    exit 1
}

echo "Step 4: Preparing Puppet runtime directory..."
# Since we're on macOS, we can't extract .deb files directly
# We'll bundle them for extraction on the target Ubuntu system
cd "${BUILD_DIR}/puppet-runtime"

echo "Step 5: Copying configuration and modules..."
# Copy our custom configuration and modules
cp -r "${SCRIPT_DIR}/config" .
cp -r "${SCRIPT_DIR}/manifests" .
cp -r "${SCRIPT_DIR}/modules" .

echo "Step 6: Creating wrapper scripts..."
# Create a wrapper script that sets up the environment for offline puppet
cat > puppet-wrapper.sh << 'WRAPPER'
#!/bin/bash
# Wrapper script for running puppet offline

# Set up Puppet paths
export PATH="/opt/puppetlabs/puppet/bin:$PATH"
export PUPPET_BASE="/opt/puppet-runtime"

# Run puppet with our configuration
exec /opt/puppetlabs/puppet/bin/puppet "$@"
WRAPPER
chmod +x puppet-wrapper.sh

# Create apply wrapper for convenience
cat > puppet-apply-wrapper.sh << 'SCRIPT'
#!/bin/bash
# Wrapper script for puppet apply
PUPPET_BASE="/opt/puppet-runtime"

# Use the installed puppet from puppetlabs
export PATH="/opt/puppetlabs/puppet/bin:$PATH"

/opt/puppetlabs/puppet/bin/puppet apply \
    --modulepath="${PUPPET_BASE}/modules" \
    --config="${PUPPET_BASE}/config/puppet.conf" \
    "${PUPPET_BASE}/manifests/site.pp" \
    --verbose \
    "$@"
SCRIPT
chmod +x puppet-apply-wrapper.sh

echo "Step 7: Bundling dependencies..."
# Bundle the .deb file for offline installation
cp "${BUILD_DIR}/puppet-agent.deb" .
cp "${BUILD_DIR}/puppet-release-noble.deb" .

# Create an install info file
cat > install-info.txt << 'INFO'
Puppet Runtime Bundle for Ubuntu 24.04 AMD64
=============================================
This bundle contains:
- Puppet agent package (puppet-agent.deb)
- Puppet release configuration (puppet-release-noble.deb)
- Custom Puppet modules and configuration
- Wrapper scripts for offline execution

The installer will install these packages locally without
requiring internet access.
INFO

echo "Step 8: Creating tarball..."
cd "${BUILD_DIR}"
tar -czf "${OUTPUT_DIR}/puppet-runtime.tar.gz" puppet-runtime/

echo "Step 9: Copying installation scripts..."
cp "${SCRIPT_DIR}/scripts/install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/post-install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/uninstall.sh" "${OUTPUT_DIR}/"

# Clean up
rm -rf "${BUILD_DIR}"

echo ""
echo "=== Build Complete ==="
echo "Output files:"
echo "  - ${OUTPUT_DIR}/puppet-runtime.tar.gz"
echo "  - ${OUTPUT_DIR}/install.sh"
echo "  - ${OUTPUT_DIR}/post-install.sh"
echo "  - ${OUTPUT_DIR}/uninstall.sh"
echo ""
echo "To deploy on Ubuntu 24.04 ${ARCH}:"
echo "  1. Copy all files from ${OUTPUT_DIR}/ to the target machine"
echo "  2. Extract: tar -xzf puppet-runtime.tar.gz -C /tmp/puppet-install"
echo "  3. Run: INSTALLER_PATH=/tmp/puppet-install sudo ./install.sh"
echo "  4. Run: sudo ./post-install.sh"