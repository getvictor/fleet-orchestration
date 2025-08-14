#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/puppet-runtime"

echo "==================================="
echo "  Apache Configuration via Puppet"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

# post-install.sh doesn't need INSTALLER_PATH since Puppet is already installed
if [ ! -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Error: Puppet runtime not found at ${PERMANENT_INSTALL_PATH}"
    echo "Please run install.sh first"
    exit 1
fi

# Use our bundled puppet from the runtime directory
PUPPET_BIN="${PERMANENT_INSTALL_PATH}/bin/puppet"
export PATH="${PERMANENT_INSTALL_PATH}/bin:/usr/local/bin:$PATH"

if [ ! -f "$PUPPET_BIN" ]; then
    echo "Error: Puppet not found at $PUPPET_BIN"
    echo "Please ensure install.sh completed successfully"
    exit 1
fi

echo "Checking Puppet installation..."
echo "Puppet version:"
$PUPPET_BIN --version || echo "Unable to determine version"
echo ""

MANIFEST_PATH="${PERMANENT_INSTALL_PATH}/manifests/site.pp"

if [ ! -f "${MANIFEST_PATH}" ]; then
    echo "Error: Puppet manifest not found at ${MANIFEST_PATH}"
    exit 1
fi

echo "Running Apache installation via Puppet..."
echo "This will:"
echo "  - Install Apache2 web server"
echo "  - Configure it to serve a test page"
echo "  - Start the Apache service"

echo ""
echo "Executing Puppet manifest..."
echo "==================================="

cd "${PERMANENT_INSTALL_PATH}"

# Apply the Puppet manifest
FACTER_var1=$FLEET_SECRET_VAR1 FACTER_var2=var2_content \
$PUPPET_BIN apply \
    --modulepath="${PERMANENT_INSTALL_PATH}/modules" \
    --config="${PERMANENT_INSTALL_PATH}/config/puppet.conf" \
    "${MANIFEST_PATH}" \
    --verbose \
    --detailed-exitcodes || RESULT=$?

# Puppet apply exit codes:
# 0: No changes
# 2: Changes applied successfully
# 4: Failures
# 6: Changes applied but also failures

if [ "${RESULT:-0}" -eq 0 ] || [ "${RESULT:-0}" -eq 2 ]; then
    echo ""
    echo "==================================="
    echo "  Configuration Complete!"
    echo "==================================="
    echo ""
    echo "Apache has been successfully installed and configured!"
    echo ""

    # Check Apache status
    if service apache2 status >/dev/null 2>&1; then
        echo "Apache Status: ✓ Running"
    else
        echo "Apache Status: Starting..."
        service apache2 start || true
    fi

    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo ""
    echo "You can access the web server at:"
    echo "  - http://localhost/"
    if [ ! -z "$IP_ADDR" ]; then
        echo "  - http://${IP_ADDR}/"
    fi

    echo ""
    echo "To check Apache status: service apache2 status"
    echo "To view Apache logs: tail -f /var/log/apache2/*.log"
else
    echo ""
    echo "==================================="
    echo "  Configuration Failed!"
    echo "==================================="
    echo ""
    echo "The Puppet manifest encountered an error (exit code: ${RESULT:-unknown})"
    echo "Please check the output above for details."
    exit 1
fi
