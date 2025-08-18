#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

echo "=== Salt Uninstallation Script ==="
echo ""

# Stop Apache if running
echo "Step 1: Stopping Apache..."
systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true

# Remove Apache
echo "Step 2: Removing Apache..."
apt-get remove -y apache2 apache2-* 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

# Clean up Apache directories
rm -rf /etc/apache2
rm -rf /var/www/html
rm -rf /var/log/apache2

# Remove Salt runtime and virtual environment
echo "Step 3: Removing Salt installation..."
# Remove the Salt virtual environment completely
rm -rf /opt/salt-venv
rm -rf /opt/salt-runtime
# Remove wrapper scripts
rm -f /usr/local/bin/salt-apply
rm -f /usr/local/bin/salt-call
rm -f /usr/local/bin/salt-minion

# Clean up Salt directories
echo "Step 4: Cleaning Salt directories..."
rm -rf /srv/salt
rm -rf /var/cache/salt
rm -rf /var/log/salt
rm -rf /etc/salt

echo ""
echo "=== Uninstallation Complete ==="
echo "Apache and Salt have been completely removed"
