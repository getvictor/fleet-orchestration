#!/bin/bash

set -e

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/chef-runtime"

echo "==================================="
echo "  Apache Configuration via Chef"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

# post-install.sh doesn't need INSTALLER_PATH since Chef is already installed
if [ ! -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Error: Chef runtime not found at ${PERMANENT_INSTALL_PATH}"
    echo "Please run install.sh first"
    exit 1
fi

export PATH="${PERMANENT_INSTALL_PATH}/chef/bin:${PATH}"
export CHEF_HOME="${PERMANENT_INSTALL_PATH}"

echo "Checking Chef installation..."
if ! command -v chef-client &> /dev/null; then
    echo "Error: chef-client command not found"
    echo "Please ensure install.sh completed successfully"
    exit 1
fi

echo "Chef version:"
chef-client --version | head -n1
echo ""

# Check if cookbook exists
COOKBOOK_PATH="${PERMANENT_INSTALL_PATH}/cookbooks/apache"
if [ ! -d "${COOKBOOK_PATH}" ]; then
    echo "Error: Apache cookbook not found at ${COOKBOOK_PATH}"
    exit 1
fi

echo "Running Apache installation via Chef..."
echo "This will:"
echo "  - Install Apache2 web server"
echo "  - Configure it to serve a test page"
echo "  - Start the Apache service"
echo ""
echo "Executing Chef Client in local mode..."
echo "==================================="

cd "${PERMANENT_INSTALL_PATH}"

# Run chef-client in local mode with the node configuration (use wrapper script)
"${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" \
    --local-mode \
    --config "${PERMANENT_INSTALL_PATH}/chef/etc/client.rb" \
    --json-attributes <(cat <<EOF
{
  "run_list": ["recipe[apache::default]"],
  "apache": {
    "server_name": "localhost"
  },
  "my_cookbook": {
    "var1": "${FLEET_SECRET_VAR1}",
    "var2": "var2_content"
  }
}
EOF
) \
    --log-level info \
    --force-formatter \
    --no-color

RESULT=$?

echo ""
echo "==================================="

if [ $RESULT -eq 0 ]; then
    echo "  Configuration Complete!"
    echo "==================================="
    echo ""
    echo "Apache has been successfully installed and configured!"
    echo ""

    # Check Apache status
    if service apache2 status >/dev/null 2>&1; then
        echo "Apache Status: ✓ Running"

        # Get IP address
        IP_ADDR=$(hostname -I | awk '{print $1}')
        echo ""
        echo "You can access the web server at:"
        echo "  - http://localhost/"
        if [ ! -z "$IP_ADDR" ]; then
            echo "  - http://${IP_ADDR}/"
        fi
    else
        echo "Warning: Apache service status could not be verified"
        echo "Try starting it manually: service apache2 start"
    fi

    echo ""
    echo "To check Apache status: service apache2 status"
    echo "To view Apache logs: tail -f /var/log/apache2/*.log"
else
    echo "  Configuration Failed!"
    echo "==================================="
    echo ""
    echo "The Chef run encountered an error."
    echo "Please check the output above for details."
    exit 1
fi
