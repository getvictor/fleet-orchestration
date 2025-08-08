#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUILD_DIR="${OUTPUT_DIR}/build"
ANSIBLE_VERSION="2.16.3"
PYTHON_VERSION="3.11"

echo "=== Ansible Runtime Builder ==="
echo "Building for: Ubuntu Linux (x86_64)"
echo "Ansible Version: ${ANSIBLE_VERSION}"
echo ""

rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}/ansible-runtime"

echo "Step 1: Creating Python virtual environment structure..."
mkdir -p "${BUILD_DIR}/ansible-runtime/ansible"
cd "${BUILD_DIR}/ansible-runtime/ansible"

cat > requirements.txt << 'EOF'
ansible==9.2.0
ansible-core==2.16.3
jinja2==3.1.3
PyYAML==6.0.1
cryptography==42.0.2
packaging==23.2
resolvelib==1.0.1
EOF

echo "Step 2: Creating standalone Ansible launcher..."
mkdir -p bin

cat > bin/ansible << 'SCRIPT'
#!/bin/bash
# Wrapper script for Ansible
ANSIBLE_RUNTIME="/opt/ansible-runtime"
export ANSIBLE_CONFIG="${ANSIBLE_RUNTIME}/ansible/etc/ansible.cfg"

# Activate virtual environment and run ansible
exec "${ANSIBLE_RUNTIME}/venv/bin/ansible" "$@"
SCRIPT

cat > bin/ansible-playbook << 'SCRIPT'
#!/bin/bash
# Wrapper script for Ansible Playbook
ANSIBLE_RUNTIME="/opt/ansible-runtime"
export ANSIBLE_CONFIG="${ANSIBLE_RUNTIME}/ansible/etc/ansible.cfg"

# Activate virtual environment and run ansible-playbook
exec "${ANSIBLE_RUNTIME}/venv/bin/ansible-playbook" "$@"
SCRIPT

cat > bin/ansible-galaxy << 'SCRIPT'
#!/bin/bash
# Wrapper script for Ansible Galaxy
ANSIBLE_RUNTIME="/opt/ansible-runtime"
export ANSIBLE_CONFIG="${ANSIBLE_RUNTIME}/ansible/etc/ansible.cfg"

# Activate virtual environment and run ansible-galaxy
exec "${ANSIBLE_RUNTIME}/venv/bin/ansible-galaxy" "$@"
SCRIPT

chmod +x bin/*

echo "Step 3: Creating Ansible configuration..."
mkdir -p etc
cat > etc/ansible.cfg << 'EOF'
[defaults]
host_key_checking = False
inventory = localhost,
remote_tmp = /tmp/.ansible-${USER}/tmp
local_tmp = /tmp/.ansible-${USER}/tmp
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/.ansible-${USER}/facts
fact_caching_timeout = 3600
retry_files_enabled = False
stdout_callback = yaml
ansible_managed = Ansible managed: {file} modified on %Y-%m-%d %H:%M:%S
deprecation_warnings = False
command_warnings = False
EOF

echo "Step 4: Copying playbooks..."
cp -r "${SCRIPT_DIR}/playbooks" "${BUILD_DIR}/ansible-runtime/"

echo "Step 5: Creating tarball..."
cd "${BUILD_DIR}"
tar -czf "${OUTPUT_DIR}/ansible-runtime.tar.gz" ansible-runtime/

echo "Step 6: Copying installation scripts..."
cp "${SCRIPT_DIR}/scripts/install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/post-install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/uninstall.sh" "${OUTPUT_DIR}/"

rm -rf "${BUILD_DIR}"

echo ""
echo "=== Build Complete ==="
echo "Output files:"
echo "  - ${OUTPUT_DIR}/ansible-runtime.tar.gz"
echo "  - ${OUTPUT_DIR}/install.sh"
echo "  - ${OUTPUT_DIR}/post-install.sh"
echo "  - ${OUTPUT_DIR}/uninstall.sh"
echo ""
echo "To deploy on Ubuntu Linux:"
echo "  1. Copy all files from ${OUTPUT_DIR}/ to the target machine"
echo "  2. Extract: tar -xzf ansible-runtime.tar.gz -C /your/install/path"
echo "  3. Run: INSTALL_PATH=/your/install/path sudo ./install.sh"
echo "  4. Run: INSTALL_PATH=/your/install/path sudo ./post-install.sh"
