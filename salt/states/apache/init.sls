# Salt state for Apache installation and configuration

# Update apt cache
update_apt_cache:
  pkg.uptodate:
    - refresh: True

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

# Install Apache and lsof packages
apache_packages:
  pkg.installed:
    - pkgs:
      - apache2
      - lsof
    - require:
      - pkg: update_apt_cache
      - user: www-data-user

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

# Check and free port 80 if needed
check_port_80:
  cmd.run:
    - name: |
        if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
          echo "Port 80 is in use, attempting to free it..."
          systemctl stop apache2 2>/dev/null || true
          service apache2 stop 2>/dev/null || true
          pkill -f apache2 2>/dev/null || true
          sleep 2
        fi
    - require:
      - pkg: apache_packages

# Configure Apache ServerName to avoid warnings
apache_servername:
  file.append:
    - name: /etc/apache2/apache2.conf
    - text: "ServerName localhost"
    - require:
      - pkg: apache_packages
    - unless: grep -q "^ServerName" /etc/apache2/apache2.conf

# Ensure Apache run directory exists
apache_run_directory:
  file.directory:
    - name: /var/run/apache2
    - user: www-data
    - group: www-data
    - mode: 755
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
        var1: {{ salt['environ.get']('FLEET_SECRET_VAR1', 'not_set') }}
        var2: {{ pillar.get('apache:var2', 'not_set') }}

# Enable and start Apache service
apache_service:
  service.running:
    - name: apache2
    - enable: True
    - require:
      - pkg: apache_packages
      - file: apache_servername
      - file: apache_run_directory
      - file: apache_index_page
    - watch:
      - file: apache_index_page
      - file: apache_servername

# Ensure Apache is actually running (fallback check)
verify_apache_running:
  cmd.run:
    - name: |
        if ! pgrep -f apache2 >/dev/null 2>&1; then
          echo "Apache not running, attempting manual start..."
          systemctl start apache2 2>&1 || \
          service apache2 start 2>&1 || \
          /usr/sbin/apache2ctl start 2>&1 || \
          echo "WARNING: Could not start Apache automatically"
          
          sleep 2
          
          if pgrep -f apache2 >/dev/null 2>&1; then
            echo "✓ Apache is now running"
          else
            echo "✗ Apache failed to start"
            echo "Check: sudo systemctl status apache2"
            echo "Logs: sudo journalctl -xeu apache2"
          fi
        else
          echo "✓ Apache is already running"
        fi
    - require:
      - service: apache_service