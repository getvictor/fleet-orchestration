# Salt state for Apache installation and configuration

# Update apt cache
update_apt_cache:
  cmd.run:
    - name: apt-get update && touch /var/cache/salt/apt-updated
    - creates: /var/cache/salt/apt-updated

# Ensure www-data user and group exist
www-data-group:
  group.present:
    - name: www-data
    - gid: 33
    - system: True

www-data-user:
  user.present:
    - name: www-data
    - uid: 33
    - gid: 33
    - home: /var/www
    - shell: /usr/sbin/nologin
    - system: True
    - require:
      - group: www-data-group

# Install Apache packages
apache_packages:
  pkg.installed:
    - pkgs:
      - apache2
      - apache2-utils
      - apache2-bin
      - apache2-data
      - lsof
    - require:
      - cmd: update_apt_cache
      - user: www-data-user

# Verify apache2.conf exists and is valid (never modify it directly!)
verify_apache_config:
  cmd.run:
    - name: |
        echo "=== Checking apache2.conf status ==="
        
        if [ ! -f /etc/apache2/apache2.conf ]; then
            echo "ERROR: apache2.conf is missing!"
            echo "Reinstalling apache2 package to restore config..."
            # Use dpkg-reconfigure to properly restore config files
            DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y -o Dpkg::Options::="--force-confmiss" apache2
            echo "Reinstallation complete"
        else
            SIZE=$(wc -c < /etc/apache2/apache2.conf)
            echo "apache2.conf exists with size: $SIZE bytes"
            if [ $SIZE -lt 1000 ]; then
                echo "WARNING: apache2.conf seems truncated (only $SIZE bytes)"
                echo "Reinstalling apache2 package to restore proper config..."
                DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y -o Dpkg::Options::="--force-confmiss" apache2
                echo "Reinstalled - new size: $(wc -c < /etc/apache2/apache2.conf) bytes"
            fi
        fi
        
        # Don't reinstall just for missing includes - the file might be from a different version
        # Just verify and report
        if ! grep -q "IncludeOptional mods-enabled" /etc/apache2/apache2.conf; then
            echo "WARNING: apache2.conf might be missing mods-enabled include"
        fi
        if ! grep -q "IncludeOptional conf-enabled" /etc/apache2/apache2.conf; then
            echo "WARNING: apache2.conf might be missing conf-enabled include"
        fi
        
        # Final verification
        if [ -f /etc/apache2/apache2.conf ]; then
            echo "✓ apache2.conf exists with $(wc -c < /etc/apache2/apache2.conf) bytes"
        else
            echo "✗ FATAL: apache2.conf is still missing after reinstall!"
            exit 1
        fi
    - require:
      - pkg: apache_packages

# Ensure mods-enabled directory exists
apache_mods_dir:
  file.directory:
    - name: /etc/apache2/mods-enabled
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: apache_packages
      - cmd: verify_apache_config

# Enable essential Apache modules with symlinks
{% for mod in ['authz_core', 'authz_host', 'auth_basic', 'access_compat', 'alias', 'dir', 'autoindex', 'env', 'mime', 'negotiation', 'setenvif', 'filter', 'deflate', 'status', 'reqtimeout', 'authn_file', 'authn_core', 'authz_user'] %}
apache_module_{{ mod }}:
  file.symlink:
    - name: /etc/apache2/mods-enabled/{{ mod }}.load
    - target: /etc/apache2/mods-available/{{ mod }}.load
    - force: True
    - makedirs: True
    - require:
      - file: apache_mods_dir

{% if mod in ['dir', 'mime', 'negotiation', 'setenvif', 'alias', 'autoindex', 'deflate', 'status', 'reqtimeout'] %}
apache_module_{{ mod }}_conf:
  file.symlink:
    - name: /etc/apache2/mods-enabled/{{ mod }}.conf
    - target: /etc/apache2/mods-available/{{ mod }}.conf
    - force: True
    - makedirs: True
    - require:
      - file: apache_module_{{ mod }}
{% endif %}
{% endfor %}

# Debug: Check what MPM modules are available
debug_mpm_modules:
  cmd.run:
    - name: |
        echo "=== Available MPM modules ===" 
        ls -la /etc/apache2/mods-available/mpm_* 2>/dev/null || echo "No MPM modules found in mods-available"
        echo ""
        echo "=== Currently enabled MPM modules ===" 
        ls -la /etc/apache2/mods-enabled/mpm_* 2>/dev/null || echo "No MPM modules enabled"
    - require:
      - pkg: apache_packages

# Disable all MPM modules first (only one can be active)
disable_mpm_event:
  file.absent:
    - name: /etc/apache2/mods-enabled/mpm_event.load
    - require:
      - pkg: apache_packages

disable_mpm_event_conf:
  file.absent:
    - name: /etc/apache2/mods-enabled/mpm_event.conf
    - require:
      - file: disable_mpm_event

disable_mpm_worker:
  file.absent:
    - name: /etc/apache2/mods-enabled/mpm_worker.load
    - require:
      - pkg: apache_packages

disable_mpm_worker_conf:
  file.absent:
    - name: /etc/apache2/mods-enabled/mpm_worker.conf
    - require:
      - file: disable_mpm_worker

# Enable MPM prefork module (most compatible)
apache_mpm_prefork:
  file.symlink:
    - name: /etc/apache2/mods-enabled/mpm_prefork.load
    - target: /etc/apache2/mods-available/mpm_prefork.load
    - force: True
    - makedirs: True
    - require:
      - file: apache_mods_dir
      - file: disable_mpm_event
      - file: disable_mpm_worker
      - cmd: debug_mpm_modules

apache_mpm_prefork_conf:
  file.symlink:
    - name: /etc/apache2/mods-enabled/mpm_prefork.conf
    - target: /etc/apache2/mods-available/mpm_prefork.conf
    - force: True
    - makedirs: True
    - require:
      - file: apache_mpm_prefork

# Verify MPM module is enabled
verify_mpm_enabled:
  cmd.run:
    - name: |
        echo "=== Verifying MPM module symlinks ===" 
        if [ -L /etc/apache2/mods-enabled/mpm_prefork.load ]; then
            echo "✓ mpm_prefork.load symlink exists"
            ls -la /etc/apache2/mods-enabled/mpm_prefork.load
            TARGET=$(readlink -f /etc/apache2/mods-enabled/mpm_prefork.load)
            echo "Target: $TARGET"
            if [ -f "$TARGET" ]; then
                echo "✓ Target file exists and contains:"
                cat "$TARGET"
            else
                echo "✗ ERROR: Target file does not exist!"
                echo "Checking for mpm_prefork module files..."
                ls -la /etc/apache2/mods-available/mpm_* 2>/dev/null || echo "No MPM modules in mods-available!"
            fi
        else
            echo "✗ mpm_prefork.load symlink missing"
        fi
        
        if [ -L /etc/apache2/mods-enabled/mpm_prefork.conf ]; then
            echo "✓ mpm_prefork.conf symlink exists"
            ls -la /etc/apache2/mods-enabled/mpm_prefork.conf
        else
            echo "✗ mpm_prefork.conf symlink missing"
        fi
        
        echo ""
        echo "=== Checking if apache2.conf includes required directories ===" 
        if grep -q "IncludeOptional mods-enabled" /etc/apache2/apache2.conf 2>/dev/null; then
            echo "✓ apache2.conf includes mods-enabled directory"
        else
            echo "✗ ERROR: apache2.conf does not include mods-enabled directory!"
            echo "File size: $(wc -c < /etc/apache2/apache2.conf 2>/dev/null || echo 0) bytes"
        fi
        if grep -q "IncludeOptional conf-enabled" /etc/apache2/apache2.conf 2>/dev/null; then
            echo "✓ apache2.conf includes conf-enabled directory"
        else
            echo "✗ ERROR: apache2.conf does not include conf-enabled directory!"
        fi
        
        echo ""
        echo "=== Custom configs in conf-enabled ===" 
        ls -la /etc/apache2/conf-enabled/ 2>/dev/null | head -10 || echo "No conf-enabled directory"
    - require:
      - file: apache_mpm_prefork
      - file: apache_mpm_prefork_conf

# Ensure Apache runtime directories exist
apache_runtime_dirs:
  file.directory:
    - names:
      - /var/run/apache2
      - /var/log/apache2
      - /var/lock/apache2
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: True
    - require:
      - pkg: apache_packages

# Ensure /var/www/html directory exists
web_root_directory:
  file.directory:
    - name: /var/www/html
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: True
    - require:
      - pkg: apache_packages

# Deploy custom index.html from template
apache_index_page:
  file.managed:
    - name: /var/www/html/index.html
    - source: salt://apache/files/index.html.jinja
    - template: jinja
    - user: www-data
    - group: www-data
    - mode: 644
    - require:
      - file: web_root_directory
    - defaults:
        server_name: {{ grains.get('fqdn', 'localhost') }}
        platform: {{ grains.get('os', 'Unknown') }}
        platform_version: {{ grains.get('osrelease', 'Unknown') }}

# Create custom ServerName configuration (proper Apache way)
apache_servername_config_file:
  file.managed:
    - name: /etc/apache2/conf-available/servername.conf
    - contents: |
        # Set ServerName to avoid Apache warning
        ServerName localhost
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: apache_packages

# Enable the ServerName configuration
apache_servername_config_enable:
  file.symlink:
    - name: /etc/apache2/conf-enabled/servername.conf
    - target: /etc/apache2/conf-available/servername.conf
    - force: True
    - makedirs: True
    - require:
      - file: apache_servername_config_file

# Pre-service check - what's the state right before we start?
pre_service_check:
  cmd.run:
    - name: |
        echo "=== Pre-service check ==="
        if [ -f /etc/apache2/apache2.conf ]; then
            echo "✓ apache2.conf exists: $(wc -c < /etc/apache2/apache2.conf) bytes"
        else
            echo "✗ CRITICAL: apache2.conf is missing right before service start!"
            echo "Checking what files exist in /etc/apache2:"
            ls -la /etc/apache2/ 2>&1 || echo "/etc/apache2 directory doesn't exist!"
        fi
    - require:
      - pkg: apache_packages
      - file: apache_runtime_dirs
      - file: apache_index_page
      - file: apache_servername_config_enable
      - file: apache_mpm_prefork
      - file: apache_mpm_prefork_conf
      - cmd: verify_mpm_enabled

# Enable and start Apache service
apache_service:
  service.running:
    - name: apache2
    - enable: True
    - require:
      - cmd: pre_service_check
    - watch:
      - file: apache_index_page

# Debug Apache startup failure
debug_apache_failure:
  cmd.run:
    - name: |
        echo "=== APACHE DEBUG INFO ==="
        echo ""
        echo "=== Apache config test ===" 
        apache2ctl configtest 2>&1 || true
        echo ""
        echo "=== Apache error log (last 20 lines) ===" 
        tail -20 /var/log/apache2/error.log 2>/dev/null || echo "No error log found"
        echo ""
        echo "=== Apache2.conf status ==="
        if [ -f /etc/apache2/apache2.conf ]; then
            echo "Size: $(wc -c < /etc/apache2/apache2.conf) bytes"
            echo "Include lines:"
            grep "Include" /etc/apache2/apache2.conf | head -5
        else
            echo "apache2.conf MISSING!"
        fi
        echo ""
        echo "=== Enabled modules (first 20) ===" 
        ls -la /etc/apache2/mods-enabled/ 2>/dev/null | head -20
        echo ""
        echo "=== Enabled configs ===" 
        ls -la /etc/apache2/conf-enabled/ 2>/dev/null | head -10
        echo ""
        echo "=== Apache service status ===" 
        systemctl status apache2 --no-pager 2>&1 || service apache2 status 2>&1 || true
        echo "=== END APACHE DEBUG INFO ==="
    - onfail:
      - service: apache_service