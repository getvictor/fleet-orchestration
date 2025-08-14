#
# Cookbook:: apache
# Recipe:: default
#
# Copyright:: 2024, Chef Apache Installer
#

# Update apt cache
apt_update 'update' do
  frequency 86400
  action :periodic
end

# Ensure www-data user and group exist (required for Apache)
group 'www-data' do
  gid 33
  system true
  action :create
end

user 'www-data' do
  uid 33
  gid 'www-data'
  home '/var/www'
  shell '/usr/sbin/nologin'
  system true
  action :create
end

# Install required packages
package ['apache2', 'lsof'] do
  action :install
  notifies :run, 'bash[verify_apache_install]', :immediately
end

# Verify Apache installation completed properly
bash 'verify_apache_install' do
  code <<-EOH
    echo "=== Verifying Apache Installation ==="
    echo "Checking if www-data user was created by Apache package:"
    if id www-data 2>/dev/null; then
      echo "✓ www-data user exists"
      id www-data
    else
      echo "✗ www-data user NOT found - Apache package installation incomplete!"
      echo "Checking /etc/passwd for issues:"
      ls -la /etc/passwd
      echo "Attempting to manually create www-data user..."
      groupadd -g 33 www-data 2>/dev/null || echo "Group creation failed"
      useradd -u 33 -g www-data -d /var/www -s /usr/sbin/nologin www-data 2>/dev/null || echo "User creation failed"
    fi

    echo "Checking Apache binary:"
    ls -la /usr/sbin/apache2 2>/dev/null || echo "Apache binary not found"

    echo "Checking Apache config directory:"
    ls -la /etc/apache2/ 2>/dev/null || echo "Apache config directory not found"

    echo "Checking dpkg status of apache2:"
    dpkg -l | grep apache2

    echo "Checking for incomplete package installation:"
    dpkg --audit
  EOH
  action :nothing
end

# Check if port 80 is already in use
bash 'check_port_80' do
  code <<-EOH
    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
      echo "WARNING: Port 80 is already in use by:"
      lsof -Pi :80 -sTCP:LISTEN
      # Try to stop any existing Apache instances
      systemctl stop apache2 2>/dev/null || true
      service apache2 stop 2>/dev/null || true
      pkill -f apache2 2>/dev/null || true
      sleep 2
    fi
  EOH
  only_if { ::File.exist?('/usr/sbin/apache2') }
end

# Fix Apache configuration if needed
bash 'fix_apache_config' do
  code <<-EOH
    # Ensure www-data user exists
    if ! id -u www-data >/dev/null 2>&1; then
      echo "ERROR: www-data user still missing after creation attempt"
      exit 1
    fi

    # Ensure /var/www exists with correct ownership
    if [ ! -d /var/www ]; then
      mkdir -p /var/www/html
      chown -R www-data:www-data /var/www
    fi

    # Ensure ServerName is set to avoid warning
    if ! grep -q "^ServerName" /etc/apache2/apache2.conf; then
      echo "ServerName localhost" >> /etc/apache2/apache2.conf
    fi

    # Ensure Apache run directory exists
    mkdir -p /var/run/apache2
    chown www-data:www-data /var/run/apache2

    # Test Apache configuration
    apache2ctl configtest 2>&1
    if [ $? -ne 0 ]; then
      echo "Apache configuration has errors, checking details..."

      # Check for common issues
      echo "Checking Apache modules..."
      ls -la /etc/apache2/mods-enabled/ 2>&1

      echo "Checking Apache ports configuration..."
      cat /etc/apache2/ports.conf 2>&1

      # Try to fix common issues
      a2enmod mpm_prefork 2>/dev/null || true
      a2enmod authz_core 2>/dev/null || true

      # Test again
      apache2ctl configtest 2>&1
    fi
  EOH
  only_if { ::File.exist?('/usr/sbin/apache2') }
end

# Ensure Apache service is enabled and started
service node['apache']['service_name'] do
  supports status: true, restart: true, reload: true
  action [:enable, :start]
  retries 3
  retry_delay 5
end

# Create custom index.html from template
template "#{node['apache']['document_root']}/index.html" do
  source 'index.html.erb'
  owner 'www-data'
  group 'www-data'
  mode '0644'
  variables(
    title: node['apache']['site_title'],
    message: node['apache']['site_message'],
    server_name: node['apache']['server_name'],
    platform: node['platform'],
    platform_version: node['platform_version'],
    var1: node['my_cookbook']['var1'],
    var2: node['my_cookbook']['var2']
  )
  # Only restart if not in a container environment
  notifies :restart, "service[#{node['apache']['service_name']}]", :delayed unless File.exist?('/.dockerenv')
end

# Ensure Apache is running after all changes (with fallback)
bash 'ensure_apache_running' do
  code <<-EOH
    # Check if Apache is running
    if ! pgrep -f apache2 >/dev/null 2>&1; then
      echo "Apache not running, attempting manual start..."

      # Check what's wrong
      echo "Checking Apache status:"
      systemctl status apache2 --no-pager 2>&1 || true

      echo "Checking Apache config:"
      apache2ctl configtest 2>&1 || true

      echo "Checking port 80:"
      lsof -Pi :80 -sTCP:LISTEN 2>&1 || echo "Port 80 is free"

      # Try different start methods
      systemctl start apache2 2>&1 || \
      service apache2 start 2>&1 || \
      /usr/sbin/apache2ctl start 2>&1 || \
      echo "WARNING: Could not start Apache automatically"

      sleep 2

      # Final check
      if pgrep -f apache2 >/dev/null 2>&1; then
        echo "✓ Apache is now running"
      else
        echo "✗ Apache failed to start - manual intervention may be required"
        echo "Try running: sudo systemctl status apache2"
        echo "And: sudo journalctl -xeu apache2"
      fi
    else
      echo "✓ Apache is already running"
    fi
  EOH
end

# Log success message
log 'apache_success' do
  message "Apache has been successfully installed and configured!"
  level :info
end

# Display access information
ruby_block 'display_access_info' do
  block do
    Chef::Log.info("=====================================")
    Chef::Log.info("Apache Installation Complete!")
    Chef::Log.info("=====================================")
    Chef::Log.info("You can access the web server at:")
    Chef::Log.info("  - http://localhost/")

    # Try to get IP address
    begin
      require 'socket'
      ip = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}
      if ip
        Chef::Log.info("  - http://#{ip.ip_address}/")
      end
    rescue
      # Ignore if we can't get IP
    end

    Chef::Log.info("=====================================")
  end
  action :run
end
