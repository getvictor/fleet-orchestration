#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/ansible-runtime"

echo "==================================="
echo "  Ansible Runtime Uninstaller"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

echo "This will remove:"
echo "  - Ansible runtime from ${PERMANENT_INSTALL_PATH}"
echo "  - System-wide Ansible symlinks"
echo "  - Apache2 web server (if installed)"
echo "  - Ansible Python packages"

echo ""
echo "Stopping Apache service..."
if systemctl is-active --quiet apache2; then
    systemctl stop apache2
    echo "✓ Apache service stopped"
else
    echo "- Apache service was not running"
fi

echo "Disabling Apache service..."
if systemctl is-enabled --quiet apache2 2>/dev/null; then
    systemctl disable apache2
    echo "✓ Apache service disabled"
else
    echo "- Apache service was not enabled"
fi

echo "Removing Apache2..."
# Get all installed apache2 packages
APACHE_PACKAGES=$(dpkg -l | grep -E '^ii.*apache2' | awk '{print $2}')

if [ -n "$APACHE_PACKAGES" ]; then
    echo "Found Apache packages:"
    echo "$APACHE_PACKAGES"
    
    # Stop Apache if running
    service apache2 stop 2>/dev/null || true
    
    # Remove all Apache packages (use echo to properly expand the variable)
    echo "$APACHE_PACKAGES" | xargs apt-get remove -y
    echo "$APACHE_PACKAGES" | xargs apt-get purge -y
    
    # Also explicitly remove common Apache packages that might be missed
    apt-get remove -y apache2 apache2-utils apache2-bin apache2-data 2>/dev/null || true
    apt-get purge -y apache2-common 2>/dev/null || true
    
    # Clean up dependencies
    apt-get autoremove -y
    
    echo "✓ Apache2 packages removed"

    # Clean up directories
    if [ -d /var/www ]; then
        rm -rf /var/www
        echo "✓ Apache web root removed"
    fi

    if [ -d /etc/apache2 ]; then
        rm -rf /etc/apache2
        echo "✓ Apache configuration removed"
    fi
    
    # Remove Apache user if exists
    if id -u www-data >/dev/null 2>&1; then
        deluser www-data 2>/dev/null || true
        echo "✓ Apache user removed"
    fi
    
    # Clean up any remaining Apache files
    rm -rf /var/log/apache2 2>/dev/null || true
    rm -rf /var/cache/apache2 2>/dev/null || true
    rm -rf /usr/lib/apache2 2>/dev/null || true
    rm -rf /usr/share/apache2 2>/dev/null || true
    
    # Remove the apache2 binary if it still exists
    if [ -f /usr/sbin/apache2 ]; then
        rm -f /usr/sbin/apache2
        echo "✓ Apache2 binary removed"
    fi
else
    echo "- Apache2 was not installed"
fi

echo "Removing Ansible runtime..."
if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    rm -rf "${PERMANENT_INSTALL_PATH}"
    echo "✓ Ansible runtime removed from ${PERMANENT_INSTALL_PATH}"
else
    echo "- Ansible runtime directory not found"
fi

echo "Removing system-wide symlinks..."
SYMLINKS=(
    "/usr/local/bin/ansible"
    "/usr/local/bin/ansible-playbook"
    "/usr/local/bin/ansible-galaxy"
)

for link in "${SYMLINKS[@]}"; do
    if [ -L "$link" ]; then
        rm -f "$link"
        echo "✓ Removed $link"
    fi
done

echo "Removing Ansible environment configuration..."
if [ -f /etc/profile.d/ansible.sh ]; then
    rm -f /etc/profile.d/ansible.sh
    echo "✓ Removed /etc/profile.d/ansible.sh"
fi

# Note: Ansible packages are in the virtual environment which will be removed with the directory

echo "Cleaning up temporary files..."
rm -rf /tmp/.ansible-*
rm -rf /root/.ansible
find /home -maxdepth 2 -name ".ansible" -type d -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "==================================="
echo "  Uninstallation Complete!"
echo "==================================="
echo ""
echo "The following have been removed:"
echo "  ✓ Ansible runtime and configuration"
echo "  ✓ Apache2 web server and configuration"
echo "  ✓ System-wide Ansible commands"
echo "  ✓ Ansible Python packages"
echo ""
echo "Your system has been cleaned up successfully."
