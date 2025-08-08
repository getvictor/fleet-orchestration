# Ansible Apache Installer Project Plan

## Overview
Build a self-contained Ansible installer that configures and launches Apache web server locally on a single machine (localhost).

**Build Environment**: macOS (current machine)  
**Target Environment**: Ubuntu Linux

## Build Outputs
1. **ansible-runtime.tar.gz** - Contains Ansible control node and playbook bundle
2. **install.sh** - Installs Ansible from extracted tar.gz contents (runs as root)
3. **post-install.sh** - Runs the Ansible playbook to configure Apache (runs as root)
4. **uninstall.sh** - Removes Ansible and Apache installation (runs as root)

## Architecture

### Package Structure (tar.gz contents)
```
ansible-runtime/
├── ansible/          # Ansible binaries and core files
│   ├── bin/         # Ansible executables
│   ├── lib/         # Python libraries
│   └── etc/         # Configuration files
└── playbooks/       # Our custom playbooks
    └── apache.yml   # Apache installation playbook
```

### Separate Scripts (not in tar.gz)
- **install.sh**: Sets up Ansible environment with proper permissions (runs as root)
- **post-install.sh**: Executes ansible-playbook for Apache setup (runs as root)
- **uninstall.sh**: Cleanup script (runs as root)

## Build Process

### Phase 1: Download Ansible Artifacts
- Download Ansible portable/standalone version for Linux x86_64
- Include all required Python dependencies for Ubuntu
- Build tar.gz on macOS for deployment to Ubuntu Linux
- Ensure compatibility with Ubuntu Linux target system

### Phase 2: Create Apache Playbook
- Write ansible playbook to:
  - Install Apache web server
  - Configure basic HTML page saying "It works!"
  - Start Apache service
  - Target: localhost only

### Phase 3: Package Creation
- Bundle Ansible + playbook into tar.gz
- Create installation scripts separately

## Technical Requirements

### Ansible Setup
- Use Ansible in standalone/portable mode for Linux x86_64
- No system-wide installation required
- Self-contained Python environment compatible with Ubuntu
- Configuration for localhost-only management
- Cross-platform build: macOS (build) → Ubuntu Linux (runtime)

### Apache Configuration
- Install Apache2 (Ubuntu package)
- Create simple HTML index page
- Configure to serve on default port (80 or 8080)
- Ensure service starts automatically via systemd

### Installation Flow (on Ubuntu Linux)
1. User extracts tar.gz to `$INSTALLER_PATH` (temporary directory)
2. User runs `sudo install.sh` to:
   - Copy Ansible runtime from temp to `/opt/ansible-runtime`
   - Install Python dependencies
   - Set up system-wide commands
3. User runs `sudo post-install.sh` to execute playbook
4. Apache server starts serving "It works!" page
5. `$INSTALLER_PATH` can be deleted after installation

## Implementation Steps

1. **Setup Build Environment**
   - Create build script to download Ansible
   - Set up directory structure

2. **Create Ansible Playbook**
   - Write apache.yml playbook
   - Include HTML template file
   - Configure for localhost execution

3. **Write Installation Scripts**
   - install.sh: Set up paths, permissions
   - post-install.sh: Run ansible-playbook command
   - uninstall.sh: Remove installations

4. **Build & Package**
   - Download Ansible artifacts
   - Bundle with playbook
   - Create tar.gz archive
   - Generate separate script files

## File Deliverables

### In Repository
```
ansible/
├── PROJECT_PLAN.md        # This document
├── build.sh               # Main build script
├── playbooks/
│   ├── apache.yml         # Apache installation playbook
│   └── files/
│       └── index.html     # "It works!" page
├── scripts/
│   ├── install.sh         # Ansible setup script
│   ├── post-install.sh    # Playbook execution script
│   └── uninstall.sh       # Cleanup script
└── output/                # Build outputs (generated)
    ├── ansible-runtime.tar.gz
    ├── install.sh
    ├── post-install.sh
    └── uninstall.sh
```

## Notes
- Ansible will run in "local" connection mode
- No SSH required since managing localhost only
- All installation scripts (install.sh, post-install.sh, uninstall.sh) run with root/sudo privileges
- Build artifacts must be Linux x86_64 compatible
- Scripts must use bash/sh syntax compatible with Ubuntu
- Scripts can perform system-wide installations and modifications
- `$INSTALLER_PATH` is a temporary directory used only during installation
- Permanent installation location: `/opt/ansible-runtime`