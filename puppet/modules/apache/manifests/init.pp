# Apache module for Puppet
class apache {
  # Update apt cache before installing
  exec { 'apt-update':
    command => '/usr/bin/apt-get update',
    before  => Package['apache2'],
  }

  # Install Apache package
  package { 'apache2':
    ensure => installed,
  }

  # Ensure Apache service is running
  service { 'apache2':
    ensure  => running,
    enable  => true,
    require => Package['apache2'],
  }

  # Create custom index.html from template
  file { '/var/www/html/index.html':
    ensure  => file,
    content => template('apache/index.html.erb'),
    owner   => 'www-data',
    group   => 'www-data',
    mode    => '0644',
    require => Package['apache2'],
    notify  => Service['apache2'],
  }

  # Remove default Ubuntu page
  file { '/var/www/html/index.nginx-debian.html':
    ensure => absent,
  }
}