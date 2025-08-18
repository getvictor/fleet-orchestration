#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUILD_DIR="${OUTPUT_DIR}/build"

echo "=== Salt Open Runtime Builder ==="
echo "Building for: Ubuntu 24.04 Linux"
echo ""

rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}/salt-runtime"

echo "Step 1: Creating Salt state structure..."
mkdir -p "${BUILD_DIR}/salt-runtime/states"
mkdir -p "${BUILD_DIR}/salt-runtime/pillar"
mkdir -p "${BUILD_DIR}/salt-runtime/config"

echo "Step 2: Copying Salt states..."
cp -r "${SCRIPT_DIR}/states/"* "${BUILD_DIR}/salt-runtime/states/" 2>/dev/null || true

echo "Step 3: Copying Salt pillar data..."
cp -r "${SCRIPT_DIR}/pillar/"* "${BUILD_DIR}/salt-runtime/pillar/" 2>/dev/null || true

echo "Step 4: Creating Salt minion configuration..."
cp "${SCRIPT_DIR}/config/minion" "${BUILD_DIR}/salt-runtime/config/minion"

echo "Step 5: Creating wrapper scripts..."
mkdir -p "${BUILD_DIR}/salt-runtime/bin"

# Create salt-call wrapper for masterless mode
cat > "${BUILD_DIR}/salt-runtime/bin/salt-apply" << 'SCRIPT'
#!/bin/bash
# Wrapper script for Salt masterless execution
SALT_RUNTIME="/opt/salt-runtime"

# Check if Salt is installed
if ! command -v salt-call &> /dev/null; then
    echo "Error: salt-minion is not installed"
    echo "Please install Salt first using the install.sh script"
    exit 1
fi

# Copy state and pillar files to Salt directories
echo "Copying Salt states and pillar data..."
cp -r "${SALT_RUNTIME}/states/"* /srv/salt/states/ 2>/dev/null || true
cp -r "${SALT_RUNTIME}/pillar/"* /srv/salt/pillar/ 2>/dev/null || true

# Apply the Salt states in masterless mode
echo "Applying Salt states..."
salt-call --local --config-dir="${SALT_RUNTIME}/config" state.apply
SCRIPT

chmod +x "${BUILD_DIR}/salt-runtime/bin/salt-apply"

echo "Step 6: Creating tarball..."
cd "${BUILD_DIR}"
tar -czf "${OUTPUT_DIR}/salt-runtime.tar.gz" salt-runtime/

echo "Step 7: Copying installation scripts..."
if [ ! -d "${SCRIPT_DIR}/scripts" ]; then
    echo "Error: scripts directory not found at ${SCRIPT_DIR}/scripts"
    echo "Please ensure scripts/install.sh, scripts/post-install.sh, and scripts/uninstall.sh exist"
    exit 1
fi

cp "${SCRIPT_DIR}/scripts/install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/post-install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/uninstall.sh" "${OUTPUT_DIR}/"

# Make scripts executable
chmod +x "${OUTPUT_DIR}/install.sh"
chmod +x "${OUTPUT_DIR}/post-install.sh"
chmod +x "${OUTPUT_DIR}/uninstall.sh"

# Cleanup
rm -rf "${BUILD_DIR}"

echo ""
echo "=== Build Complete ==="
echo "Output files:"
echo "  - ${OUTPUT_DIR}/salt-runtime.tar.gz"
echo "  - ${OUTPUT_DIR}/install.sh"
echo "  - ${OUTPUT_DIR}/post-install.sh"
echo "  - ${OUTPUT_DIR}/uninstall.sh"
echo ""
echo "To deploy on Ubuntu Linux:"
echo "  1. Copy all files from ${OUTPUT_DIR}/ to the target machine"
echo "  2. Run: INSTALLER_PATH=/your/path sudo ./install.sh"
echo "  3. Run: INSTALLER_PATH=/your/path sudo ./post-install.sh"