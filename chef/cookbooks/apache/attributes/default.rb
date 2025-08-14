# Apache Cookbook Default Attributes

# Server configuration
default['apache']['server_name'] = 'localhost'
default['apache']['server_admin'] = 'webmaster@localhost'
default['apache']['document_root'] = '/var/www/html'

# Port configuration
default['apache']['port'] = 80

# Service configuration
default['apache']['service_name'] = 'apache2'
default['apache']['package_name'] = 'apache2'

# Site configuration
default['apache']['site_title'] = 'It works!'
default['apache']['site_message'] = 'Apache has been successfully installed via Chef'
