#!/bin/bash

set -e

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/chef-runtime"

echo "==================================="
echo "  Chef Runtime Uninstaller"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

echo "This will remove:"
echo "  - Chef runtime from ${PERMANENT_INSTALL_PATH}"
echo "  - System-wide Chef symlinks"
echo "  - Apache2 web server (if installed)"
echo "  - Chef working directories"

echo ""
echo "Stopping Apache service..."
if service apache2 status >/dev/null 2>&1; then
    service apache2 stop
    echo "✓ Apache service stopped"
else
    echo "- Apache service was not running"
fi

echo "Disabling Apache service..."
if systemctl is-enabled apache2 >/dev/null 2>&1; then
    systemctl disable apache2 >/dev/null 2>&1
    echo "✓ Apache service disabled"
else
    echo "- Apache service was not enabled"
fi

echo "Removing Apache2..."
if dpkg -l | grep -q apache2; then
    apt-get remove -y apache2 apache2-utils apache2-bin
    apt-get purge -y apache2 apache2-utils apache2-bin
    apt-get autoremove -y
    echo "✓ Apache2 removed"
    
    if [ -d /var/www/html ]; then
        rm -rf /var/www/html
        echo "✓ Apache web root removed"
    fi
    
    if [ -d /etc/apache2 ]; then
        rm -rf /etc/apache2
        echo "✓ Apache configuration removed"
    fi
    
    if [ -d /var/log/apache2 ]; then
        rm -rf /var/log/apache2
        echo "✓ Apache logs removed"
    fi
else
    echo "- Apache2 was not installed"
fi

echo "Removing Chef runtime..."
if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    rm -rf "${PERMANENT_INSTALL_PATH}"
    echo "✓ Chef runtime removed from ${PERMANENT_INSTALL_PATH}"
else
    echo "- Chef runtime directory not found"
fi

echo "Removing system-wide symlinks..."
SYMLINKS=(
    "/usr/local/bin/chef-client"
    "/usr/local/bin/chef-solo"
    "/usr/local/bin/knife"
    "/usr/local/bin/chef-apply"
)

for link in "${SYMLINKS[@]}"; do
    if [ -L "$link" ]; then
        rm -f "$link"
        echo "✓ Removed $link"
    fi
done

echo "Removing Chef environment configuration..."
if [ -f /etc/profile.d/chef.sh ]; then
    rm -f /etc/profile.d/chef.sh
    echo "✓ Removed /etc/profile.d/chef.sh"
fi

echo "Removing Chef working directories..."
if [ -d /var/chef ]; then
    rm -rf /var/chef
    echo "✓ Removed /var/chef"
fi

if [ -d /var/log/chef ]; then
    rm -rf /var/log/chef
    echo "✓ Removed /var/log/chef"
fi

# Clean up any Chef cache in user directories
echo "Cleaning up Chef cache files..."
rm -rf /root/.chef 2>/dev/null || true
rm -rf /home/*/.chef 2>/dev/null || true
rm -rf /tmp/chef-* 2>/dev/null || true

echo ""
echo "==================================="
echo "  Uninstallation Complete!"
echo "==================================="
echo ""
echo "The following have been removed:"
echo "  ✓ Chef runtime and configuration"
echo "  ✓ Apache2 web server and configuration"
echo "  ✓ System-wide Chef commands"
echo "  ✓ Chef working directories"
echo ""
echo "Your system has been cleaned up successfully."