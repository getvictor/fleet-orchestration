# Salt Apache Installer Project Plan

## Overview
Build a self-contained Salt Open installer that configures and launches Apache web server locally on a single machine (masterless mode).

**Build Environment**: macOS (current machine)  
**Target Environment**: Ubuntu 24.04 Linux

## Build Outputs
1. **salt-runtime.tar.gz** - Contains Salt states and configuration
2. **install.sh** - Installs Salt and sets up the environment (runs as root)
3. **post-install.sh** - Runs Salt states to configure Apache (runs as root)
4. **uninstall.sh** - Removes Salt and Apache installation (runs as root)

## Architecture

### Package Structure (tar.gz contents)
```
salt-runtime/
├── states/           # Salt state files
│   └── apache/      # Apache installation states
│       ├── init.sls
│       └── files/
│           └── index.html
├── pillar/          # Salt pillar data
│   └── apache.sls
└── config/          # Salt configuration
    └── minion       # Masterless minion config
```

### Separate Scripts (not in tar.gz)
- **install.sh**: Installs Salt minion and sets up environment (runs as root)
- **post-install.sh**: Executes salt-call for Apache setup (runs as root)
- **uninstall.sh**: Cleanup script (runs as root)

## Build Process

### Phase 1: Create Salt States
- Write Salt state files to:
  - Install Apache web server
  - Configure basic HTML page saying "It works!"
  - Start Apache service
  - Target: localhost only

### Phase 2: Package Creation
- Bundle Salt states into tar.gz
- Create installation scripts separately

## Technical Requirements

### Salt Setup
- Use Salt Open in masterless mode (salt-call --local)
- No Salt Master required
- Self-contained state execution
- Configuration for standalone execution

### Apache Configuration
- Install Apache2 (Ubuntu package)
- Create simple HTML index page
- Configure to serve on default port (80)
- Ensure service starts automatically via systemd

### Installation Flow (on Ubuntu Linux)
1. User extracts tar.gz to `$INSTALLER_PATH` (temporary directory)
2. User runs `sudo INSTALLER_PATH=/path/to/temp ./install.sh` to:
   - Install Salt minion from official repository
   - Copy states from temp to `/srv/salt`
   - Set up masterless configuration
3. User runs `sudo ./post-install.sh` to execute states
4. Apache server starts serving "It works!" page
5. `$INSTALLER_PATH` can be deleted after installation

## Implementation Steps

1. **Setup Build Environment**
   - Create build script to package states
   - Set up directory structure

2. **Create Salt States**
   - Write apache state with init.sls
   - Include HTML template file
   - Configure for local execution

3. **Write Installation Scripts**
   - install.sh: Install Salt, set up paths
   - post-install.sh: Run salt-call command
   - uninstall.sh: Remove installations

4. **Build & Package**
   - Package states and config
   - Create tar.gz archive
   - Generate separate script files

## File Deliverables

### In Repository
```
salt/
├── PROJECT_PLAN.md        # This document
├── build.sh               # Main build script
├── states/
│   └── apache/           # Apache installation states
│       ├── init.sls
│       └── files/
│           └── index.html.jinja
├── pillar/
│   └── apache.sls        # Pillar data
├── config/
│   └── minion            # Minion configuration
├── scripts/
│   ├── install.sh        # Salt setup script
│   ├── post-install.sh   # State execution script
│   └── uninstall.sh      # Cleanup script
├── test-deployment.sh    # Docker test script
├── stop-containers.sh    # Container cleanup
└── output/               # Build outputs (generated)
    ├── salt-runtime.tar.gz
    ├── install.sh
    ├── post-install.sh
    └── uninstall.sh
```

## Notes
- Salt will run in "masterless" mode (salt-call --local)
- No Salt Master required since managing localhost only
- All installation scripts run with root/sudo privileges
- Scripts must use bash/sh syntax compatible with Ubuntu
- `$INSTALLER_PATH` is a temporary directory used only during installation
- Permanent installation location: `/srv/salt` (standard Salt location)