# Chef Apache Installer Project Plan

## Overview
Build a self-contained Chef installer that configures and launches Apache web server locally on a single machine (localhost).

**Build Environment**: macOS (current machine)  
**Target Environment**: Ubuntu Linux

## Build Outputs
1. **chef-runtime.tar.gz** - Contains Chef Infra Client and cookbook bundle
2. **install.sh** - Installs Chef from extracted tar.gz contents (runs as root)
3. **post-install.sh** - Runs Chef client to configure Apache (runs as root)
4. **uninstall.sh** - Removes Chef and Apache installation (runs as root)

## Architecture

### Package Structure (tar.gz contents)
```
chef-runtime/
├── chef/             # Chef binaries and core files
│   ├── bin/         # Chef executables
│   ├── embedded/    # Embedded Ruby and dependencies
│   └── etc/         # Configuration files
└── cookbooks/       # Our custom cookbooks
    └── apache/      # Apache installation cookbook
        ├── recipes/
        ├── templates/
        └── attributes/
```

### Separate Scripts (not in tar.gz)
- **install.sh**: Sets up Chef environment with proper permissions (runs as root)
- **post-install.sh**: Executes chef-client for Apache setup (runs as root)
- **uninstall.sh**: Cleanup script (runs as root)

## Build Process

### Phase 1: Download Chef Artifacts
- Download Chef Infra Client for Linux x86_64
- Include embedded Ruby and all dependencies for Ubuntu
- Build tar.gz on macOS for deployment to Ubuntu Linux
- Ensure compatibility with Ubuntu Linux target system

### Phase 2: Create Apache Cookbook
- Write Chef cookbook to:
  - Install Apache web server
  - Configure basic HTML page saying "It works!"
  - Start Apache service
  - Target: localhost only

### Phase 3: Package Creation
- Bundle Chef + cookbook into tar.gz
- Create installation scripts separately

## Technical Requirements

### Chef Setup
- Use Chef Infra Client in standalone/local mode for Linux x86_64
- No Chef Server required
- Self-contained Ruby environment compatible with Ubuntu
- Configuration for chef-solo or chef-zero (local mode)
- Cross-platform build: macOS (build) → Ubuntu Linux (runtime)

### Apache Configuration
- Install Apache2 (Ubuntu package)
- Create simple HTML index page
- Configure to serve on default port (80 or 8080)
- Ensure service starts automatically via systemd

### Installation Flow (on Ubuntu Linux)
1. User extracts tar.gz to `$INSTALL_PATH` (temporary directory)
2. User runs `sudo install.sh` to:
   - Copy Chef runtime from temp to `/opt/chef-runtime`
   - Set up embedded Ruby environment
   - Set up system-wide commands
3. User runs `sudo post-install.sh` to execute cookbook
4. Apache server starts serving "It works!" page
5. `$INSTALL_PATH` can be deleted after installation

## Implementation Steps

1. **Setup Build Environment**
   - Create build script to download Chef
   - Set up directory structure

2. **Create Chef Cookbook**
   - Write apache cookbook with recipes
   - Include HTML template file
   - Configure for local execution

3. **Write Installation Scripts**
   - install.sh: Set up paths, permissions
   - post-install.sh: Run chef-client command
   - uninstall.sh: Remove installations

4. **Build & Package**
   - Download Chef artifacts
   - Bundle with cookbook
   - Create tar.gz archive
   - Generate separate script files

## File Deliverables

### In Repository
```
chef/
├── PROJECT_PLAN.md        # This document
├── build.sh               # Main build script
├── cookbooks/
│   └── apache/           # Apache installation cookbook
│       ├── recipes/
│       │   └── default.rb
│       ├── templates/
│       │   └── default/
│       │       └── index.html.erb
│       └── attributes/
│           └── default.rb
├── scripts/
│   ├── install.sh         # Chef setup script
│   ├── post-install.sh    # Cookbook execution script
│   └── uninstall.sh       # Cleanup script
└── output/                # Build outputs (generated)
    ├── chef-runtime.tar.gz
    ├── install.sh
    ├── post-install.sh
    └── uninstall.sh
```

## Notes
- Chef will run in "local" mode (chef-zero)
- No Chef Server required since managing localhost only
- All installation scripts (install.sh, post-install.sh, uninstall.sh) run with root/sudo privileges
- Build artifacts must be Linux x86_64 compatible
- Scripts must use bash/sh syntax compatible with Ubuntu
- Scripts can perform system-wide installations and modifications
- `$INSTALL_PATH` is a temporary directory used only during installation
- Permanent installation location: `/opt/chef-runtime`