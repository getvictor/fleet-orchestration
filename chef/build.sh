#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUILD_DIR="${OUTPUT_DIR}/build"
CHEF_VERSION="18.8.9"
# Target Ubuntu 24.04 on AMD64
ARCH="amd64"
UBUNTU_VERSION="24.04"
CHEF_DOWNLOAD_URL="https://packages.chef.io/files/stable/chef/${CHEF_VERSION}/ubuntu/${UBUNTU_VERSION}/chef_${CHEF_VERSION}-1_${ARCH}.deb"

echo "=== Chef Runtime Builder ==="
echo "Building for: Ubuntu ${UBUNTU_VERSION} Linux (${ARCH})"
echo "Chef Version: ${CHEF_VERSION}"
echo ""

rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}/chef-runtime"

echo "Step 1: Downloading Chef Infra Client..."
cd "${BUILD_DIR}"
curl -L -o chef.deb "${CHEF_DOWNLOAD_URL}"

echo "Step 2: Extracting Chef package..."
# Extract the .deb package
mkdir -p chef-extract
cd chef-extract
ar -x ../chef.deb

# Handle different compression formats (gz, xz, zst)
if [ -f data.tar.gz ]; then
    tar -xzf data.tar.gz
elif [ -f data.tar.xz ]; then
    tar -xJf data.tar.xz
elif [ -f data.tar.zst ]; then
    tar --zstd -xf data.tar.zst
else
    echo "Error: Unknown data archive format"
    ls -la
    exit 1
fi

echo "Step 3: Copying Chef files..."
# Copy the opt/chef directory which contains the embedded Ruby and Chef
# Temporarily disable error checking for the copy operation
set +e
cp -R opt/chef "${BUILD_DIR}/chef-runtime/chef" 2>/dev/null
COPY_RESULT=$?
set -e

# Check if at least the main directories were copied
if [ ! -d "${BUILD_DIR}/chef-runtime/chef/embedded" ]; then
    echo "Error: embedded directory not copied properly"
    exit 1
fi
if [ ! -d "${BUILD_DIR}/chef-runtime/chef/bin" ]; then
    echo "Error: bin directory not copied properly"
    exit 1
fi
echo "Chef files copied successfully (symlink warnings ignored)"

echo "Step 4: Creating Chef configuration..."
mkdir -p "${BUILD_DIR}/chef-runtime/chef/etc"

# Create client.rb for local mode
cat > "${BUILD_DIR}/chef-runtime/chef/etc/client.rb" << 'EOF'
# Chef Client Configuration for Local Mode
local_mode true
chef_zero.enabled true
chef_repo_path "/opt/chef-runtime/cookbooks"
cookbook_path ["/opt/chef-runtime/cookbooks"]
node_path "/opt/chef-runtime/nodes"
log_level :info
log_location STDOUT
file_cache_path "/var/chef/cache"
file_backup_path "/var/chef/backup"
node_name "localhost"
EOF

# Create solo.rb for chef-solo (alternative to local mode)
cat > "${BUILD_DIR}/chef-runtime/chef/etc/solo.rb" << 'EOF'
# Chef Solo Configuration
cookbook_path ["/opt/chef-runtime/cookbooks"]
node_path "/opt/chef-runtime/nodes"
log_level :info
log_location STDOUT
file_cache_path "/var/chef/cache"
file_backup_path "/var/chef/backup"
EOF

echo "Step 5: Creating wrapper scripts..."
mkdir -p "${BUILD_DIR}/chef-runtime/chef/bin-wrappers"

# Create chef-client wrapper
cat > "${BUILD_DIR}/chef-runtime/chef/bin-wrappers/chef-client" << 'SCRIPT'
#!/bin/bash
# Wrapper script for Chef Client
CHEF_RUNTIME="/opt/chef-runtime"
export PATH="${CHEF_RUNTIME}/chef/embedded/bin:${CHEF_RUNTIME}/chef/bin:${PATH}"
export GEM_HOME="${CHEF_RUNTIME}/chef/embedded/lib/ruby/gems/3.1.0"
export GEM_PATH="${CHEF_RUNTIME}/chef/embedded/lib/ruby/gems/3.1.0"
export RUBY_ROOT="${CHEF_RUNTIME}/chef/embedded"
export RUBYLIB="${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0:${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0/x86_64-linux:${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0:${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0/x86_64-linux"

# Accept Chef license automatically
export CHEF_LICENSE="accept-silent"

# Clean environment for child processes
export CHEF_CLEAN_ENV="true"

# Execute Ruby directly - RPATH is fixed by patchelf during install
exec "${CHEF_RUNTIME}/chef/embedded/bin/ruby" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0/x86_64-linux" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0/x86_64-linux" \
  "${CHEF_RUNTIME}/chef/bin/chef-client" "$@"
SCRIPT

# Create chef-solo wrapper
cat > "${BUILD_DIR}/chef-runtime/chef/bin-wrappers/chef-solo" << 'SCRIPT'
#!/bin/bash
# Wrapper script for Chef Solo
CHEF_RUNTIME="/opt/chef-runtime"
export PATH="${CHEF_RUNTIME}/chef/embedded/bin:${CHEF_RUNTIME}/chef/bin:${PATH}"
export GEM_HOME="${CHEF_RUNTIME}/chef/embedded/lib/ruby/gems/3.1.0"
export GEM_PATH="${CHEF_RUNTIME}/chef/embedded/lib/ruby/gems/3.1.0"
export RUBY_ROOT="${CHEF_RUNTIME}/chef/embedded"
export RUBYLIB="${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0:${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0/x86_64-linux:${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0:${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0/x86_64-linux"

# Accept Chef license automatically
export CHEF_LICENSE="accept-silent"

# Clean environment for child processes
export CHEF_CLEAN_ENV="true"

# Execute Ruby directly - RPATH is fixed by patchelf during install
exec "${CHEF_RUNTIME}/chef/embedded/bin/ruby" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/site_ruby/3.1.0/x86_64-linux" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0" \
  -I"${CHEF_RUNTIME}/chef/embedded/lib/ruby/3.1.0/x86_64-linux" \
  "${CHEF_RUNTIME}/chef/bin/chef-solo" "$@"
SCRIPT

# Create knife wrapper
cat > "${BUILD_DIR}/chef-runtime/chef/bin-wrappers/knife" << 'SCRIPT'
#!/bin/bash
# Wrapper script for Knife
CHEF_RUNTIME="/opt/chef-runtime"
export PATH="${CHEF_RUNTIME}/chef/embedded/bin:${CHEF_RUNTIME}/chef/bin:${PATH}"
export GEM_HOME="${CHEF_RUNTIME}/chef/embedded/lib/ruby/gems/3.1.0"
export GEM_PATH="${CHEF_RUNTIME}/chef/embedded/lib/ruby/gems/3.1.0"
export RUBY_ROOT="${CHEF_RUNTIME}/chef/embedded"

# Don't set LD_LIBRARY_PATH to avoid conflicts with system tools
exec "${CHEF_RUNTIME}/chef/embedded/bin/ruby" "${CHEF_RUNTIME}/chef/embedded/bin/knife" "$@"
SCRIPT

chmod +x "${BUILD_DIR}/chef-runtime/chef/bin-wrappers/"*

echo "Step 6: Copying cookbooks..."
cp -r "${SCRIPT_DIR}/cookbooks" "${BUILD_DIR}/chef-runtime/"

echo "Step 7: Creating node configuration..."
mkdir -p "${BUILD_DIR}/chef-runtime/nodes"
cat > "${BUILD_DIR}/chef-runtime/nodes/localhost.json" << 'EOF'
{
  "run_list": ["recipe[apache::default]"],
  "apache": {
    "server_name": "localhost"
  }
}
EOF

echo "Step 8: Creating tarball..."
cd "${BUILD_DIR}"
tar -czf "${OUTPUT_DIR}/chef-runtime.tar.gz" chef-runtime/

echo "Step 9: Copying installation scripts..."
cp "${SCRIPT_DIR}/scripts/install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/post-install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/uninstall.sh" "${OUTPUT_DIR}/"

# Cleanup
rm -rf "${BUILD_DIR}"

echo ""
echo "=== Build Complete ==="
echo "Output files:"
echo "  - ${OUTPUT_DIR}/chef-runtime.tar.gz"
echo "  - ${OUTPUT_DIR}/install.sh"
echo "  - ${OUTPUT_DIR}/post-install.sh"
echo "  - ${OUTPUT_DIR}/uninstall.sh"
echo ""
echo "To deploy on Ubuntu Linux:"
echo "  1. Copy all files from ${OUTPUT_DIR}/ to the target machine"
echo "  2. Extract: tar -xzf chef-runtime.tar.gz -C /your/install/path"
echo "  3. Run: INSTALLER_PATH=/your/install/path sudo ./install.sh"
echo "  4. Run: INSTALLER_PATH=/your/install/path sudo ./post-install.sh"
