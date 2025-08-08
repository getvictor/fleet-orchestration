# Ansible Runtime Package

This project creates a portable, self-contained Ansible runtime package for Ubuntu Linux systems. It packages Ansible with all dependencies into a distributable format that can be installed on target systems without requiring internet access during installation.

## Architecture Overview

```
ansible/
├── build.sh                 # Build script (runs on development machine)
├── scripts/
│   ├── install.sh          # Installation script (runs on target machine)
│   ├── post-install.sh     # Post-installation configuration (runs on target)
│   └── uninstall.sh        # Uninstallation script (runs on target)
├── playbooks/
│   └── apache.yml          # Sample Apache playbook
└── output/                 # Generated build artifacts
    ├── ansible-runtime.tar.gz
    ├── install.sh
    ├── post-install.sh
    └── uninstall.sh
```

## Ansible Product Details

### What Version of Ansible Are We Using?

We are using **Ansible 9.2.0** which includes **ansible-core 2.16.3**. This is the community version of Ansible, not Ansible Tower or AWX.

### Ansible Package Components

The package includes these specific Python packages:
- `ansible==9.2.0` - The main Ansible package (community edition)
- `ansible-core==2.16.3` - Core Ansible functionality
- `jinja2==3.1.3` - Template engine for Ansible
- `PyYAML==6.0.1` - YAML parser for playbooks
- `cryptography==42.0.2` - Cryptographic library for secure connections
- `packaging==23.2` - Version handling utilities
- `resolvelib==1.0.1` - Dependency resolver

### Installation Method

Ansible is installed using a **Python virtual environment (venv)** approach:
1. A Python 3 virtual environment is created at `/opt/ansible-runtime/venv`
2. Ansible and dependencies are installed via pip inside this virtual environment
3. Wrapper scripts are created to activate the venv and run Ansible commands

This approach ensures:
- No system Python packages are modified
- Clean isolation from system dependencies
- No pip warnings about breaking system packages
- Easy uninstallation by removing the directory

## Script Detailed Breakdown

### 1. build.sh - Package Builder

**Purpose:** Creates the distributable Ansible package on your development machine.

**What it does:**
1. **Creates package structure** (`/output/build/ansible-runtime/`)
2. **Generates requirements.txt** with exact Ansible versions
3. **Creates wrapper scripts** for ansible, ansible-playbook, and ansible-galaxy
   - These wrappers activate the virtual environment before running commands
4. **Configures Ansible** with a pre-configured ansible.cfg file
5. **Copies playbooks** from the playbooks/ directory
6. **Creates tarball** (`ansible-runtime.tar.gz`) containing everything
7. **Copies installation scripts** to output directory

**Key settings in ansible.cfg:**
```ini
host_key_checking = False         # Skip SSH host key verification
inventory = localhost,            # Default to localhost
gathering = smart                 # Smart fact gathering
fact_caching = jsonfile          # Cache facts in JSON
deprecation_warnings = False     # Suppress deprecation warnings
```

**Output artifacts:**
- `ansible-runtime.tar.gz` - Main package (contains Ansible files, not Ansible itself)
- `install.sh` - Installation script
- `post-install.sh` - Post-installation script
- `uninstall.sh` - Uninstallation script

### 2. install.sh - Ansible Installer

**Purpose:** Installs Ansible and the runtime package on the target Ubuntu system.

**Prerequisites:**
- Ubuntu 20.04 or 22.04
- Root/sudo privileges
- INSTALL_PATH environment variable (temporary extraction location)

**What it does:**

1. **Validates environment**
   - Checks for root privileges
   - Verifies INSTALL_PATH is set
   - Confirms ansible-runtime directory exists in INSTALL_PATH

2. **Installs system dependencies** (if missing):
   ```bash
   apt-get install -y python3-minimal python3-pip python3-venv
   ```

3. **Copies files to permanent location**
   - From: `$INSTALL_PATH/ansible-runtime` (temporary)
   - To: `/opt/ansible-runtime` (permanent)

4. **Creates Python virtual environment**
   ```bash
   python3 -m venv /opt/ansible-runtime/venv
   ```

5. **Installs Ansible in virtual environment**
   ```bash
   /opt/ansible-runtime/venv/bin/pip install -r requirements.txt
   ```
   This installs Ansible 9.2.0 and all dependencies inside the venv

6. **Creates system-wide symlinks**
   ```bash
   ln -sf /opt/ansible-runtime/ansible/bin/ansible /usr/local/bin/ansible
   ln -sf /opt/ansible-runtime/ansible/bin/ansible-playbook /usr/local/bin/ansible-playbook
   ln -sf /opt/ansible-runtime/ansible/bin/ansible-galaxy /usr/local/bin/ansible-galaxy
   ```

7. **Sets up environment**
   - Creates `/etc/profile.d/ansible.sh` with ANSIBLE_CONFIG export
   - Makes Ansible available system-wide

**Important:** The INSTALL_PATH is temporary and can be deleted after installation. The permanent installation is always at `/opt/ansible-runtime`.

### 3. post-install.sh - Apache Configuration

**Purpose:** Demonstrates Ansible functionality by installing and configuring Apache web server.

**What it does:**

1. **Validates Ansible installation**
   - Checks `/opt/ansible-runtime` exists
   - Verifies ansible-playbook command works

2. **Runs Apache playbook**
   ```bash
   ansible-playbook /opt/ansible-runtime/playbooks/apache.yml \
     --connection=local \
     --inventory="localhost,"
   ```

3. **The Apache playbook**:
   - Updates apt cache
   - Installs Apache2 package
   - Detects if systemd is available (handles Docker containers)
   - Starts Apache service appropriately
   - Creates a custom index.html page
   - Verifies Apache is responding on port 80

4. **Reports results**
   - Shows Apache status
   - Displays access URLs

### 4. uninstall.sh - Complete Removal

**Purpose:** Cleanly removes Ansible and Apache from the system.

**What it does:**

1. **Stops and removes Apache2** (if installed)
   ```bash
   systemctl stop apache2
   apt-get remove -y apache2 apache2-utils apache2-bin
   rm -rf /var/www/html /etc/apache2
   ```

2. **Removes Ansible runtime**
   ```bash
   rm -rf /opt/ansible-runtime
   ```

3. **Removes system symlinks**
   ```bash
   rm -f /usr/local/bin/ansible*
   ```

4. **Cleans up environment**
   ```bash
   rm -f /etc/profile.d/ansible.sh
   rm -rf /tmp/.ansible-*
   ```

## Key Design Decisions

### Why Virtual Environment?

1. **Isolation**: Keeps Ansible separate from system Python packages
2. **No Root Pip**: Avoids "externally-managed-environment" errors in modern Ubuntu
3. **Clean Uninstall**: Simply remove the directory to uninstall everything
4. **Version Control**: Exact control over Ansible and dependency versions

### Why This Ansible Version?

- **Ansible 9.2.0**: Latest stable community version at time of creation
- **ansible-core 2.16.3**: LTS version with good stability
- **Community Edition**: Free, open-source, no licensing requirements

### Why Wrapper Scripts?

The wrapper scripts (ansible, ansible-playbook, ansible-galaxy) handle:
- Activating the virtual environment
- Setting ANSIBLE_CONFIG environment variable
- Executing the actual Ansible command from the venv

Example wrapper:
```bash
#!/bin/bash
ANSIBLE_RUNTIME="/opt/ansible-runtime"
export ANSIBLE_CONFIG="${ANSIBLE_RUNTIME}/ansible/etc/ansible.cfg"
exec "${ANSIBLE_RUNTIME}/venv/bin/ansible" "$@"
```

## Testing

The test script provided:

- **test-deployment.sh**: Full integration test with Docker containers

The test script:
1. Start an Ubuntu Docker container
2. Install the Ansible package
3. Run the Apache playbook
4. Verify Apache is working
5. Test uninstallation
6. Clean up containers

## Requirements

### Build Machine (where you run build.sh)
- Bash shell
- tar command
- Any OS (macOS, Linux, WSL)

### Target Machine (where you install)
- Ubuntu 20.04 or 22.04
- Python 3.8+ (or will be installed)
- sudo/root access
- At least 100MB free space in /opt

### For Testing
- Docker installed and running
- Port 8888 available

## Security Considerations

- Ansible is installed only in `/opt/ansible-runtime`
- No system packages are modified (except Apache if post-install.sh is run)
- Virtual environment prevents package conflicts
- All operations require root/sudo (by design for system configuration)

## Troubleshooting

### "INSTALL_PATH not set" error
Set the environment variable to your extraction directory:
```bash
export INSTALL_PATH=/tmp/ansible-extract
```

### "pip externally managed" warnings
This is why we use virtual environments - no such warnings will appear.

### Apache not starting in Docker
The playbook detects containerized environments and uses appropriate commands.

### Port 8888 already in use
Stop any existing containers:
```bash
docker ps -aq --filter "name=ansible-" | xargs -r docker rm -f
```

## License

This packaging system is provided as-is for Ansible deployment automation.
