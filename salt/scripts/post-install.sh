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

# Show pillar data for debugging
echo "Step 2: Testing Salt pillar data..."
salt-call --local pillar.items

# Apply Salt states
echo "Step 3: Applying Salt states..."
echo "This will install and configure Apache..."

# Export environment variable if provided
if [ ! -z "$FLEET_SECRET_VAR1" ]; then
    export FLEET_SECRET_VAR1="$FLEET_SECRET_VAR1"
    echo "Using FLEET_SECRET_VAR1 from environment"
fi

# Capture salt-call output
SALT_OUTPUT=$(mktemp)
if salt-call --local --config-dir="${SALT_RUNTIME}/config" state.apply pillar='{"var1":"${FLEET_SECRET_VAR1}", "var2":"var2_content"}' 2>&1 | tee "$SALT_OUTPUT"; then
    echo "Salt states applied successfully"
else
    echo ""
    echo "=== SALT STATE APPLICATION FAILED ==="
    echo "Extracting relevant debug information..."
    
    # Extract only the debug_apache_failure output if it exists
    if grep -q "=== APACHE DEBUG INFO ===" "$SALT_OUTPUT"; then
        echo ""
        echo "Apache Debug Information:"
        sed -n '/=== APACHE DEBUG INFO ===/,/=== END APACHE DEBUG INFO ===/p' "$SALT_OUTPUT"
    fi
    
    # Show any error messages
    echo ""
    echo "Error Summary:"
    grep -E "(ERROR|Failed|error:|failed:|No MPM loaded|Permission denied|not found)" "$SALT_OUTPUT" | head -20
    
    # Show failed states summary
    echo ""
    grep -A 2 "Failed:" "$SALT_OUTPUT" | head -10
    
    rm -f "$SALT_OUTPUT"
    echo "=== END OF DEBUG OUTPUT ==="
    exit 1
fi
rm -f "$SALT_OUTPUT"

# Check if Apache is running
echo ""
echo "Step 4: Verifying Apache installation..."
# Check using multiple methods since systemctl might not be available
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet apache2; then
    echo "✓ Apache is running (systemctl)"
    APACHE_RUNNING=true
elif service apache2 status 2>/dev/null | grep -q "running"; then
    echo "✓ Apache is running (service)"
    APACHE_RUNNING=true
elif pgrep -f apache2 >/dev/null 2>&1; then
    echo "✓ Apache is running (process found)"
    APACHE_RUNNING=true
else
    echo "✗ Apache is not running"
    APACHE_RUNNING=false
fi

if [ "$APACHE_RUNNING" = "true" ]; then
    echo ""
    echo "Apache has been successfully deployed!"
    echo "You can access it at: http://localhost"
    echo ""
    # Show what's listening on port 80
    echo "Services on port 80:"
    lsof -i :80 | grep LISTEN || echo "No service listening on port 80"
else
    echo "Checking Apache status..."
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status apache2 --no-pager || true
    else
        service apache2 status || true
    fi
fi

echo ""
echo "=== Post-Installation Complete ==="
