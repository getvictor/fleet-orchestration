#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if INSTALLER_PATH is set
if [ -z "$INSTALLER_PATH" ]; then
    echo "Error: INSTALLER_PATH environment variable must be set"
    echo "Usage: INSTALLER_PATH=/path/to/installer sudo ./post-install.sh"
    exit 1
fi

SALT_RUNTIME="/opt/salt-runtime"

echo "=== Salt Post-Installation Script ==="
echo ""

# Check if Salt is installed
if [ ! -d "$SALT_RUNTIME" ]; then
    echo "Error: Salt runtime not found at $SALT_RUNTIME"
    echo "Please run install.sh first"
    exit 1
fi

# Copy states and pillar to Salt directories
echo "Step 1: Copying Salt states and pillar data..."
cp -r "${SALT_RUNTIME}/states/"* /srv/salt/states/ 2>/dev/null || true
cp -r "${SALT_RUNTIME}/pillar/"* /srv/salt/pillar/ 2>/dev/null || true

# Apply Salt states
echo "Step 2: Applying Salt states..."
echo "This will install and configure Apache..."

# Export environment variable if provided
if [ ! -z "$FLEET_SECRET_VAR1" ]; then
    export FLEET_SECRET_VAR1="$FLEET_SECRET_VAR1"
fi

# Apply Salt states - fail immediately if this fails
if ! salt-call --local --config-dir="${SALT_RUNTIME}/config" state.apply pillar='{"var1":"${FLEET_SECRET_VAR1}", "var2":"var2_content"}'; then
    echo ""
    echo "ERROR: Salt state application failed"
    exit 1
fi

# Check if Apache is running
echo ""
echo "Step 3: Verifying Apache installation..."
# Check using multiple methods since systemctl might not be available
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet apache2; then
    echo "✓ Apache is running"
elif service apache2 status 2>/dev/null | grep -q "running"; then
    echo "✓ Apache is running"
elif pgrep -f apache2 >/dev/null 2>&1; then
    echo "✓ Apache is running"
else
    echo "ERROR: Apache is not running"
    exit 1
fi

echo ""
echo "=== Post-Installation Complete ==="
