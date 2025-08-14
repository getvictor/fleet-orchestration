#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/puppet-runtime"

echo "==================================="
echo "  Puppet Runtime Uninstaller"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

echo "This will remove:"
echo "  - Puppet runtime from ${PERMANENT_INSTALL_PATH}"
echo "  - Puppet agent and repository"
echo "  - Apache2 web server (if installed)"
echo "  - All Puppet configuration"

echo ""
echo "Stopping Apache service..."
if systemctl is-active --quiet apache2 2>/dev/null; then
    systemctl stop apache2
    echo "✓ Apache service stopped"
else
    service apache2 stop 2>/dev/null || true
    echo "- Apache service stopped"
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
    
    # Remove all Apache packages
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

echo "Removing Puppet agent..."
if dpkg -l | grep -q puppet-agent; then
    apt-get remove -y puppet-agent
    apt-get purge -y puppet-agent
    echo "✓ Puppet agent removed"
else
    echo "- Puppet agent was not installed"
fi

echo "Removing Puppet repository..."
if dpkg -l | grep -q puppet-release; then
    apt-get remove -y puppet-release
    apt-get purge -y puppet-release
    echo "✓ Puppet repository removed"
    
    # Clean up apt sources
    rm -f /etc/apt/sources.list.d/puppet*.list
    apt-get update
else
    echo "- Puppet repository was not installed"
fi

echo "Removing Puppet runtime..."
if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    rm -rf "${PERMANENT_INSTALL_PATH}"
    echo "✓ Puppet runtime removed from ${PERMANENT_INSTALL_PATH}"
else
    echo "- Puppet runtime directory not found"
fi

echo "Removing Puppet directories..."
# Remove Puppet directories
PUPPET_DIRS=(
    "/opt/puppetlabs"
    "/etc/puppetlabs"
    "/var/log/puppetlabs"
    "/var/lib/puppet"
    "/var/log/puppet"
)

for dir in "${PUPPET_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        echo "✓ Removed $dir"
    fi
done

echo "Removing system-wide wrappers and symlinks..."
rm -f /usr/local/bin/puppet-apply
echo "✓ Removed /usr/local/bin/puppet-apply"

# Remove Puppet symlinks from /usr/local/bin
for cmd in puppet facter hiera; do
    if [ -L "/usr/local/bin/$cmd" ] || [ -f "/usr/local/bin/$cmd" ]; then
        rm -f "/usr/local/bin/$cmd"
        echo "✓ Removed /usr/local/bin/$cmd"
    fi
done

# Remove any puppet executables from system paths
which puppet >/dev/null 2>&1 && {
    PUPPET_PATH=$(which puppet)
    if [[ "$PUPPET_PATH" == "/usr/local/bin/puppet" ]] || [[ "$PUPPET_PATH" == "/usr/bin/puppet" ]]; then
        rm -f "$PUPPET_PATH"
        echo "✓ Removed puppet from $PUPPET_PATH"
    fi
}

echo "Removing Puppet environment configuration..."
if [ -f /etc/profile.d/puppet.sh ]; then
    rm -f /etc/profile.d/puppet.sh
    echo "✓ Removed /etc/profile.d/puppet.sh"
fi

# Clean up any remaining Puppet files
echo "Cleaning up temporary files..."
rm -rf /tmp/puppet* 2>/dev/null || true
find /home -maxdepth 2 -name ".puppet" -type d -exec rm -rf {} + 2>/dev/null || true

# Final cleanup of dependencies
echo "Running final cleanup..."
apt-get autoremove -y

echo ""
echo "==================================="
echo "  Uninstallation Complete!"
echo "==================================="
echo ""
echo "The following have been removed:"
echo "  ✓ Puppet runtime and configuration"
echo "  ✓ Puppet agent and repository"
echo "  ✓ Apache2 web server and configuration"
echo "  ✓ All Puppet-related files"
echo ""
echo "Your system has been cleaned up successfully."