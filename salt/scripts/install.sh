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
    echo "Usage: INSTALLER_PATH=/path/to/installer sudo ./install.sh"
    exit 1
fi

INSTALLER_DIR="$INSTALLER_PATH"
PERMANENT_INSTALL_PATH="/opt"

echo "=== Salt Installation Script ==="
echo "Installing from: $INSTALLER_DIR"
echo ""

# Update package list
echo "Step 1: Updating package list..."
apt-get update

# Install Python and dependencies
echo "Step 2: Installing Python and dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-jinja2 \
    python3-yaml \
    python3-msgpack \
    python3-zmq \
    python3-pycryptodome \
    curl \
    lsof

# Install Salt via pip in a virtual environment to avoid system package conflicts
echo "Step 3: Installing Salt via pip..."
python3 -m venv /opt/salt-venv
/opt/salt-venv/bin/pip install --upgrade pip
# Install Salt with all required dependencies
# Note: Salt has many dependencies that need to be explicitly installed
# Dependencies are pinned to specific versions for reproducibility
/opt/salt-venv/bin/pip install \
    pyyaml==6.0.2 \
    tornado==6.4.1 \
    looseversion==1.3.0 \
    jinja2==3.1.4 \
    msgpack==1.1.0 \
    pyzmq==26.2.0 \
    cryptography==43.0.1 \
    distro==1.9.0 \
    psutil==6.0.0 \
    packaging==24.1 \
    salt==3007.6

# Create wrapper scripts for Salt commands
echo "Creating Salt command wrappers..."
cat > /usr/local/bin/salt-call << 'WRAPPER'
#!/bin/bash
exec /opt/salt-venv/bin/salt-call "$@"
WRAPPER
chmod +x /usr/local/bin/salt-call

cat > /usr/local/bin/salt-minion << 'WRAPPER'
#!/bin/bash
exec /opt/salt-venv/bin/salt-minion "$@"
WRAPPER
chmod +x /usr/local/bin/salt-minion

# No service to stop since we installed via pip
echo "Step 4: Configuring Salt for masterless mode..."

# Extract Salt runtime
echo "Step 5: Extracting Salt runtime..."
cd "$INSTALLER_DIR"
tar -xzf salt-runtime.tar.gz -C "$PERMANENT_INSTALL_PATH"

# Create Salt directories
echo "Step 6: Creating Salt directories..."
mkdir -p /srv/salt/states
mkdir -p /srv/salt/pillar
mkdir -p /var/cache/salt/minion
mkdir -p /var/log/salt
mkdir -p /etc/salt/minion.d

# Copy minion configuration
echo "Step 7: Configuring Salt for masterless mode..."
cp "${PERMANENT_INSTALL_PATH}/salt-runtime/config/minion" /etc/salt/minion

# Create symlink for convenience
ln -sf "${PERMANENT_INSTALL_PATH}/salt-runtime/bin/salt-apply" /usr/local/bin/salt-apply

echo ""
echo "=== Salt Installation Complete ==="
echo "Salt has been installed in masterless mode"
echo "Configuration: /etc/salt/minion"
echo "States directory: /srv/salt/states"
echo "Pillar directory: /srv/salt/pillar"
echo ""
echo "To apply Salt states, run: salt-apply"
echo "Or use: salt-call --local state.apply"
