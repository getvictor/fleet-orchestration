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

# Check if Puppet is installed - try multiple locations
if [ -f "/opt/puppetlabs/puppet/bin/puppet" ]; then
    PUPPET_BIN="/opt/puppetlabs/puppet/bin/puppet"
    export PATH="/opt/puppetlabs/puppet/bin:$PATH"
elif [ -f "/usr/bin/puppet" ]; then
    PUPPET_BIN="/usr/bin/puppet"
else
    echo "Error: Puppet agent not found"
    echo "Please ensure install.sh completed successfully"
    exit 1
fi

echo "Checking Puppet installation..."
echo "Puppet version:"
puppet --version || echo "Unable to determine version"
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
puppet apply \
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