# Puppet Runtime Package

This project creates a portable, self-contained Puppet runtime package for Ubuntu 24.04 AMD64 systems. It packages Puppet manifests and modules into a distributable format that can be installed on target systems to manage configuration using Puppet.

## Architecture Overview

```
puppet/
├── build.sh                    # Build script (runs on development machine)
├── scripts/
│   ├── install.sh             # Installation script (runs on target machine)
│   ├── post-install.sh        # Post-installation configuration (runs on target)
│   └── uninstall.sh           # Uninstallation script (runs on target)
├── manifests/
│   └── site.pp                # Main Puppet manifest
├── modules/
│   └── apache/
│       ├── manifests/
│       │   └── init.pp        # Apache module manifest
│       └── templates/
│           └── index.html.erb # Apache index page template
└── output/                    # Generated build artifacts
    ├── puppet-runtime.tar.gz
    ├── install.sh
    ├── post-install.sh
    └── uninstall.sh
```

## Puppet Product Details

### What Version of Puppet Are We Using?

We are using **Puppet 7 or 8** (latest available) from the official Puppet repository for Ubuntu 24.04 (Noble). This is the open-source version of Puppet, not Puppet Enterprise.

### Puppet Components

The package includes:
- **Puppet Agent** - The Puppet client that applies configurations
- **Puppet Manifests** - Declarative configuration files (.pp)
- **Puppet Modules** - Reusable components (Apache module)
- **Templates** - ERB templates for dynamic content

### Installation Method

Puppet is installed using the official APT repository:
1. Downloads `puppet-release-noble.deb` from https://apt.puppet.com/
2. Installs the repository configuration
3. Installs puppet-agent package via apt-get
4. Copies manifests and modules to `/opt/puppet-runtime`

## Script Detailed Breakdown

### 1. build.sh - Package Builder

**Purpose:** Creates the distributable Puppet package on your development machine.

**What it does:**
1. **Creates package structure** (`/output/build/puppet-runtime/`)
2. **Generates puppet.conf** configuration file
3. **Creates site.pp manifest** for node classification
4. **Creates Apache module** with init.pp and templates
5. **Creates wrapper script** for puppet apply
6. **Creates tarball** (`puppet-runtime.tar.gz`)
7. **Copies installation scripts** to output directory

**Output artifacts:**
- `puppet-runtime.tar.gz` - Main package with manifests and modules
- `install.sh` - Installation script
- `post-install.sh` - Post-installation script
- `uninstall.sh` - Uninstallation script

### 2. install.sh - Puppet Installer

**Purpose:** Installs Puppet and the runtime package on Ubuntu 24.04 AMD64.

**Prerequisites:**
- Ubuntu 24.04 (verified at runtime)
- AMD64 architecture (verified at runtime)
- Root/sudo privileges
- INSTALLER_PATH environment variable
- Internet connection (for Puppet repository)

**What it does:**

1. **Validates environment**
   - Checks Ubuntu version (must be 24.04)
   - Checks architecture (must be AMD64)
   - Verifies INSTALLER_PATH is set

2. **Installs dependencies**
   ```bash
   apt-get install -y wget gnupg
   ```

3. **Sets up Puppet repository**
   ```bash
   wget https://apt.puppet.com/puppet-release-noble.deb
   dpkg -i puppet-release-noble.deb
   apt-get update
   ```

4. **Installs Puppet agent**
   ```bash
   apt-get install -y puppet-agent
   ```

5. **Copies files to permanent location**
   - From: `$INSTALLER_PATH/puppet-runtime` (temporary)
   - To: `/opt/puppet-runtime` (permanent)

6. **Creates wrapper scripts**
   - `/usr/local/bin/puppet-apply` for easy manifest application

7. **Sets up environment**
   - Adds `/opt/puppetlabs/bin` to PATH via `/etc/profile.d/puppet.sh`

### 3. post-install.sh - Apache Configuration

**Purpose:** Demonstrates Puppet functionality by applying manifests to install Apache.

**What it does:**

1. **Validates Puppet installation**
   - Checks `/opt/puppet-runtime` exists
   - Verifies puppet command works

2. **Applies Puppet manifest**
   ```bash
   puppet apply \
     --modulepath=/opt/puppet-runtime/modules \
     --config=/opt/puppet-runtime/config/puppet.conf \
     /opt/puppet-runtime/manifests/site.pp
   ```

3. **The Puppet manifest**:
   - Installs Apache2 package
   - Ensures Apache service is running
   - Creates custom index.html from template
   - Manages file permissions

4. **Reports results**
   - Shows Apache status
   - Displays access URLs

### 4. uninstall.sh - Complete Removal

**Purpose:** Cleanly removes Puppet and Apache from the system.

**What it does:**

1. **Removes Apache2**
   - Stops and disables service
   - Removes all Apache packages
   - Cleans up directories

2. **Removes Puppet**
   ```bash
   apt-get remove -y puppet-agent puppet-release
   ```

3. **Removes Puppet runtime**
   ```bash
   rm -rf /opt/puppet-runtime
   rm -rf /opt/puppetlabs
   ```

4. **Cleans up configuration**
   - Removes wrapper scripts
   - Removes environment settings
   - Cleans temporary files

## Key Design Decisions

### Why Puppet?

1. **Declarative**: Describes desired state, not procedures
2. **Idempotent**: Safe to run multiple times
3. **Resource Abstraction**: Platform-independent resource types
4. **Mature**: Well-established configuration management tool

### Why Ubuntu 24.04 Only?

- Simplified testing and support
- Uses latest Puppet repository (puppet-release-noble.deb)
- Consistent behavior across deployments
- AMD64 architecture for compatibility

### Puppet Apply vs Client-Server

Using `puppet apply` for standalone mode:
- No Puppet server required
- Simpler deployment
- Suitable for single-node configurations
- Can be extended to client-server later

## Testing

**test-deployment.sh**: Full integration test with Docker
- Starts Ubuntu 24.04 container
- Installs Puppet package
- Applies Apache manifest
- Verifies Apache is working
- Tests uninstallation

## Requirements

### Build Machine
- Bash shell
- tar command
- Any OS (macOS, Linux, WSL)

### Target Machine
- Ubuntu 24.04 (Noble Numbat)
- AMD64 architecture
- sudo/root access
- Internet connection for initial setup
- At least 200MB free space

### For Testing
- Docker installed and running
- Port 8889 available

## Usage

### Building the Package
```bash
cd puppet
chmod +x build.sh
./build.sh
```

### Installing on Target
```bash
# Copy files to target machine
scp output/* user@target:/tmp/

# On target machine
cd /tmp
tar -xzf puppet-runtime.tar.gz -C /tmp
INSTALLER_PATH=/tmp sudo ./install.sh
sudo ./post-install.sh
```

### Uninstalling
```bash
sudo ./uninstall.sh
```

## Troubleshooting

### "INSTALLER_PATH not set" error
```bash
export INSTALLER_PATH=/tmp
```

### Puppet command not found
Ensure PATH includes Puppet:
```bash
export PATH="/opt/puppetlabs/bin:$PATH"
```

### Apache not starting
Check if port 80 is in use:
```bash
netstat -tlnp | grep :80
```

### Repository download fails
Check internet connectivity and DNS resolution.

## Puppet Manifest Structure

### site.pp
```puppet
node default {
  include apache
}
```

### apache/init.pp
```puppet
class apache {
  package { 'apache2':
    ensure => installed,
  }
  
  service { 'apache2':
    ensure  => running,
    enable  => true,
    require => Package['apache2'],
  }
  
  file { '/var/www/html/index.html':
    ensure  => file,
    content => template('apache/index.html.erb'),
    require => Package['apache2'],
    notify  => Service['apache2'],
  }
}
```

## License

This packaging system is provided as-is for Puppet deployment automation.