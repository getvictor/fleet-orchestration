#!/bin/bash

set -e

# Permanent installation location
PERMANENT_INSTALL_PATH="/opt/chef-runtime"

echo "==================================="
echo "  Chef Runtime Installer"
echo "==================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

if [ -z "$INSTALLER_PATH" ]; then
    echo "Error: INSTALLER_PATH environment variable is not set"
    echo "Usage: INSTALLER_PATH=/path/to/temp/extract sudo ./install.sh"
    echo "Note: INSTALLER_PATH should be the temporary directory where you extracted the tar.gz"
    exit 1
fi

if [ ! -d "${INSTALLER_PATH}" ]; then
    echo "Error: ${INSTALLER_PATH} does not exist"
    exit 1
fi

if [ ! -d "${INSTALLER_PATH}/chef-runtime" ]; then
    echo "Error: chef-runtime directory not found at ${INSTALLER_PATH}/chef-runtime"
    echo "Please extract chef-runtime.tar.gz to ${INSTALLER_PATH} first:"
    echo "  tar -xzf chef-runtime.tar.gz -C ${INSTALLER_PATH}"
    exit 1
fi

echo "Checking system requirements..."

# Check for required system libraries
REQUIRED_PACKAGES=""

if ! dpkg -l | grep -q libssl; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libssl3"
fi

if ! dpkg -l | grep -q libc6; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libc6"
fi

if ! dpkg -l | grep -q libgcc-s1; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libgcc-s1"
fi

if ! dpkg -l | grep -q libstdc++6; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libstdc++6"
fi

# Chef also requires libyaml for YAML parsing
if ! dpkg -l | grep -q libyaml-0-2; then
    REQUIRED_PACKAGES="${REQUIRED_PACKAGES} libyaml-0-2"
fi

if [ ! -z "${REQUIRED_PACKAGES}" ]; then
    echo "Installing required system libraries..."
    apt-get update
    apt-get install -y ${REQUIRED_PACKAGES}
fi

echo "✓ System requirements satisfied"

echo ""
echo "Installing Chef runtime from temporary location to ${PERMANENT_INSTALL_PATH}..."

# Check if permanent location already exists
if [ -d "${PERMANENT_INSTALL_PATH}" ]; then
    echo "Warning: ${PERMANENT_INSTALL_PATH} already exists - will be overwritten"
    rm -rf "${PERMANENT_INSTALL_PATH}"
fi

# Create permanent directory and copy files
echo "Copying files to permanent location..."
mkdir -p "$(dirname ${PERMANENT_INSTALL_PATH})"
cp -r "${INSTALLER_PATH}/chef-runtime" "${PERMANENT_INSTALL_PATH}"

echo "Setting up permissions..."
chmod -R 755 "${PERMANENT_INSTALL_PATH}"
# Only chmod actual files, not symlinks
find "${PERMANENT_INSTALL_PATH}/chef/bin/" -type f -exec chmod +x {} \; 2>/dev/null || true
chmod +x "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/"*

# Set up library path for embedded Ruby using patchelf
echo "Setting up embedded library paths..."
if [ -d "${PERMANENT_INSTALL_PATH}/chef/embedded/lib" ]; then
    # Check if libruby exists
    if ls "${PERMANENT_INSTALL_PATH}/chef/embedded/lib"/libruby.so.* >/dev/null 2>&1; then
        echo "Found Ruby libraries in embedded/lib"
        
        # Install patchelf and file command if not present
        MISSING_TOOLS=""
        if ! command -v patchelf &> /dev/null; then
            MISSING_TOOLS="patchelf"
        fi
        if ! command -v file &> /dev/null; then
            MISSING_TOOLS="${MISSING_TOOLS} file"
        fi
        
        if [ ! -z "${MISSING_TOOLS}" ]; then
            echo "Installing required tools: ${MISSING_TOOLS}"
            apt-get update >/dev/null 2>&1
            apt-get install -y ${MISSING_TOOLS} >/dev/null 2>&1
        fi
        
        # Fix RPATH in Ruby binary to look for libraries in embedded/lib
        if command -v patchelf &> /dev/null; then
            echo "Fixing Ruby binary RPATH..."
            patchelf --set-rpath "${PERMANENT_INSTALL_PATH}/chef/embedded/lib" \
                     "${PERMANENT_INSTALL_PATH}/chef/embedded/bin/ruby" 2>/dev/null || true
            
            # Also fix any other binaries that might need it
            if command -v file &> /dev/null; then
                for binary in "${PERMANENT_INSTALL_PATH}/chef/embedded/bin/"*; do
                    if [ -f "$binary" ] && [ -x "$binary" ]; then
                        # Check if it's an ELF binary
                        if file "$binary" 2>/dev/null | grep -q "ELF"; then
                            patchelf --set-rpath "${PERMANENT_INSTALL_PATH}/chef/embedded/lib:/usr/lib/x86_64-linux-gnu" \
                                     "$binary" 2>/dev/null || true
                        fi
                    fi
                done
                
                # Also fix Ruby extension modules (.so files)
                echo "Fixing Ruby extension modules..."
                find "${PERMANENT_INSTALL_PATH}/chef/embedded/lib/ruby" -name "*.so" -type f 2>/dev/null | while read -r sofile; do
                    if file "$sofile" 2>/dev/null | grep -q "ELF"; then
                        patchelf --set-rpath "${PERMANENT_INSTALL_PATH}/chef/embedded/lib:/usr/lib/x86_64-linux-gnu" \
                                 "$sofile" 2>/dev/null || true
                    fi
                done
            else
                # Fallback: just fix known important binaries
                for name in ruby erb gem irb rdoc ri; do
                    binary="${PERMANENT_INSTALL_PATH}/chef/embedded/bin/${name}"
                    if [ -f "$binary" ]; then
                        patchelf --set-rpath "${PERMANENT_INSTALL_PATH}/chef/embedded/lib:/usr/lib/x86_64-linux-gnu" \
                                 "$binary" 2>/dev/null || true
                    fi
                done
            fi
            echo "✓ Binary RPATH fixed - no LD_LIBRARY_PATH needed"
        else
            echo "Warning: patchelf not available, falling back to wrapper scripts"
        fi
    else
        echo "Warning: libruby.so not found in embedded/lib"
    fi
    
    # Remove any old ld.so.conf.d entry
    rm -f /etc/ld.so.conf.d/chef-embedded.conf
    
    echo "✓ Library paths configured"
fi

# Create necessary directories for Chef
echo "Creating Chef working directories..."
mkdir -p /var/chef/cache
mkdir -p /var/chef/backup
mkdir -p /var/log/chef
chown -R root:root /var/chef
chmod -R 755 /var/chef

echo "Creating system-wide symlinks..."
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" /usr/local/bin/chef-client
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-solo" /usr/local/bin/chef-solo
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/knife" /usr/local/bin/knife
ln -sf "${PERMANENT_INSTALL_PATH}/chef/bin/chef-apply" /usr/local/bin/chef-apply

echo "Setting up Chef environment..."
cat > /etc/profile.d/chef.sh << EOF
# Chef Environment Configuration
export CHEF_HOME="${PERMANENT_INSTALL_PATH}"
export PATH="${PERMANENT_INSTALL_PATH}/chef/bin:\${PATH}"
EOF
chmod +x /etc/profile.d/chef.sh

# Verify the installation
echo ""
echo "Verifying Chef installation..."
export PATH="${PERMANENT_INSTALL_PATH}/chef/bin:${PATH}"

# Use the wrapper script for verification
if "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" --version >/dev/null 2>&1; then
    echo "✓ Chef Client is installed"
    "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" --version | head -n1
else
    echo "✗ Chef Client verification failed"
    # Try to debug the issue
    echo "Debug: Checking if Ruby exists..."
    ls -la "${PERMANENT_INSTALL_PATH}/chef/embedded/bin/ruby" 2>/dev/null || echo "Ruby not found"
    echo "Debug: Checking for libruby in embedded/lib..."
    ls -la "${PERMANENT_INSTALL_PATH}/chef/embedded/lib"/libruby* 2>/dev/null || echo "libruby not found in embedded/lib"
    echo "Debug: Checking wrapper script..."
    ls -la "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" 2>/dev/null || echo "Wrapper not found"
    echo "Debug: Testing Ruby directly..."
    "${PERMANENT_INSTALL_PATH}/chef/embedded/bin/ruby" --version 2>&1 || echo "Ruby execution failed"
    echo "Debug: Checking for missing libraries..."
    ldd "${PERMANENT_INSTALL_PATH}/chef/embedded/bin/ruby" 2>&1 | grep "not found" || echo "All libraries appear present"
    echo "Debug: Testing wrapper script with error output..."
    "${PERMANENT_INSTALL_PATH}/chef/bin-wrappers/chef-client" --version 2>&1 || true
    exit 1
fi

echo ""
echo "==================================="
echo "  Installation Complete!"
echo "==================================="
echo ""
echo "Chef has been installed to: ${PERMANENT_INSTALL_PATH}"
echo "Configuration file: ${PERMANENT_INSTALL_PATH}/chef/etc/client.rb"
echo "Cookbooks location: ${PERMANENT_INSTALL_PATH}/cookbooks"
echo ""
echo "The temporary directory ${INSTALLER_PATH} can now be safely deleted."
echo ""
echo "You can now run:"
echo "  - chef-client --version"
echo "  - chef-solo --version"
echo "  - knife --version"
