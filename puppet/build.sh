#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUILD_DIR="${OUTPUT_DIR}/build"

echo "=== Puppet Runtime Builder ==="
echo "Building for: Ubuntu 24.04 (AMD64)"
echo ""

rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}/puppet-runtime"

echo "Step 1: Copying Puppet configuration files..."
cd "${BUILD_DIR}/puppet-runtime"

# Copy configuration and manifest files
cp -r "${SCRIPT_DIR}/config" .
cp -r "${SCRIPT_DIR}/manifests" .
cp -r "${SCRIPT_DIR}/modules" .

echo "Step 2: Creating wrapper script..."
cat > puppet-apply-wrapper.sh << 'SCRIPT'
#!/bin/bash
# Wrapper script for puppet apply
export PATH="/opt/puppetlabs/bin:$PATH"
PUPPET_BASE="/opt/puppet-runtime"

# Apply the manifest
/opt/puppetlabs/bin/puppet apply \
    --modulepath="${PUPPET_BASE}/modules" \
    --config="${PUPPET_BASE}/config/puppet.conf" \
    "${PUPPET_BASE}/manifests/site.pp" \
    --verbose \
    "$@"
SCRIPT
chmod +x puppet-apply-wrapper.sh

echo "Step 3: Creating tarball..."
cd "${BUILD_DIR}"
tar -czf "${OUTPUT_DIR}/puppet-runtime.tar.gz" puppet-runtime/

echo "Step 4: Copying installation scripts..."
cp "${SCRIPT_DIR}/scripts/install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/post-install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/uninstall.sh" "${OUTPUT_DIR}/"

rm -rf "${BUILD_DIR}"

echo ""
echo "=== Build Complete ==="
echo "Output files:"
echo "  - ${OUTPUT_DIR}/puppet-runtime.tar.gz"
echo "  - ${OUTPUT_DIR}/install.sh"
echo "  - ${OUTPUT_DIR}/post-install.sh"
echo "  - ${OUTPUT_DIR}/uninstall.sh"
echo ""
echo "To deploy on Ubuntu 24.04 AMD64:"
echo "  1. Copy all files from ${OUTPUT_DIR}/ to the target machine"
echo "  2. Extract: tar -xzf puppet-runtime.tar.gz -C /your/install/path"
echo "  3. Run: INSTALLER_PATH=/your/install/path sudo ./install.sh"
echo "  4. Run: sudo ./post-install.sh"