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

# Install Apache package
package node['apache']['package_name'] do
  action :install
end

# Ensure Apache service is enabled and started
service node['apache']['service_name'] do
  supports status: true, restart: true, reload: true
  action [:enable, :start]
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
    platform_version: node['platform_version']
  )
  notifies :restart, "service[#{node['apache']['service_name']}]", :delayed
end

# Ensure Apache is running after all changes
service node['apache']['service_name'] do
  action :start
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
