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

apache_mpm_prefork_conf:
  file.symlink:
    - name: /etc/apache2/mods-enabled/mpm_prefork.conf
    - target: /etc/apache2/mods-available/mpm_prefork.conf
    - force: True
    - makedirs: True
    - require:
      - file: apache_mpm_prefork


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

# Enable and start Apache service
apache_service:
  service.running:
    - name: apache2
    - enable: True
    - require:
      - pkg: apache_packages
      - file: apache_runtime_dirs
      - file: apache_index_page
      - file: apache_servername_config_enable
      - file: apache_mpm_prefork
      - file: apache_mpm_prefork_conf
    - watch:
      - file: apache_index_page

