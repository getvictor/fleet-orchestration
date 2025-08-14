# Puppet Runtime Package Project Plan

## Overview
Create a self-contained Puppet installer package that can be deployed to Ubuntu Linux systems (20.04, 22.04, 24.04) to manage system configuration. Similar to the Ansible and Chef implementations, this will install Puppet and demonstrate its functionality by configuring Apache.

## Project Structure
```
puppet/
├── build.sh                    # Build script (runs on macOS)
├── scripts/
│   ├── install.sh              # Installation script
│   ├── post-install.sh         # Post-installation (runs Apache manifest)
│   └── uninstall.sh            # Uninstallation script
├── manifests/
│   └── site.pp                 # Main Puppet manifest
├── modules/
│   └── apache/
│       └── manifests/
│           └── init.pp         # Apache module
└── output/
    ├── puppet-runtime.tar.gz   # Generated package
    ├── install.sh              # Copied installation script
    ├── post-install.sh         # Copied post-installation script
    └── uninstall.sh            # Copied uninstallation script
```

## Key Components

### 1. Build System (build.sh)
- Creates puppet-runtime.tar.gz containing:
  - Puppet repository configuration
  - Puppet manifests and modules
  - Configuration files
- Copies installation scripts to output/
- Runs on macOS, targets Ubuntu Linux

### 2. Installation (install.sh)
- Installs from temporary `$INSTALLER_PATH` to permanent `/opt/puppet-runtime`
- Downloads and configures Puppet repository from https://apt.puppet.com/puppet-release-noble.deb
- Installs Puppet agent package
- Sets up Puppet configuration
- Creates wrapper scripts

### 3. Post-Installation (post-install.sh)
- Applies Puppet manifest to install Apache
- Demonstrates Puppet functionality
- Configures Apache with custom page

### 4. Uninstallation (uninstall.sh)
- Removes Puppet packages
- Removes Apache if installed
- Cleans up all configuration

## Technical Requirements

### Target System
- Ubuntu 24.04 (Noble Numbat)
- AMD64 architecture
- Root/sudo access
- Internet connection for initial package download

### Puppet Version
- Latest Puppet 7 or 8 from official repository
- Using puppet-release-noble.deb for Ubuntu repository setup

### Apache Configuration
- Install Apache2 web server
- Configure custom index.html page
- Start and enable Apache service
- Handle both systemd and non-systemd environments

## Installation Flow
1. User extracts tar.gz to `$INSTALLER_PATH` (temporary directory)
2. User runs `sudo install.sh` to:
   - Download Puppet repository package
   - Install Puppet agent
   - Copy files to `/opt/puppet-runtime`
   - Set up Puppet configuration
3. User runs `sudo post-install.sh` to apply Apache manifest
4. Apache server starts serving custom page
5. `$INSTALLER_PATH` can be deleted after installation

## Key Differences from Ansible/Chef

### Puppet Specifics
- Uses declarative manifests (.pp files)
- Resource-based configuration model
- Can run in standalone mode (puppet apply) or client-server mode
- Built-in resource types for common tasks

### Installation Method
- Uses official Puppet APT repository
- Installs via apt-get after repository setup
- No Python virtual environment needed (unlike Ansible)
- Simpler than Chef (no workstation/server components)

## Testing Strategy
- test-deployment.sh: Full integration test with Docker
- Tests on Ubuntu 20.04, 22.04, and 24.04
- Verifies Puppet installation
- Verifies Apache configuration
- Tests uninstallation completeness

## Success Criteria
- Puppet installs without errors
- Apache is successfully configured via Puppet
- Custom page displays "It works!"
- Clean uninstallation removes all components
- Works on all target Ubuntu versions
- No interactive prompts (fully automated)