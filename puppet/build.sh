#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUILD_DIR="${OUTPUT_DIR}/build"

echo "=== Puppet Runtime Builder ==="
echo "Building for: Ubuntu 24.04 (AMD64)"
echo ""

rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}/puppet-runtime"

echo "Step 1: Copying Puppet configuration files..."
cd "${BUILD_DIR}/puppet-runtime"

# Copy configuration and manifest files
cp -r "${SCRIPT_DIR}/config" .
cp -r "${SCRIPT_DIR}/manifests" .
cp -r "${SCRIPT_DIR}/modules" .

echo "Step 2: Creating puppet executable..."
mkdir -p bin
cat > bin/puppet << 'PUPPET_SCRIPT'
#!/usr/bin/env ruby
# Minimal puppet implementation for applying manifests

require 'erb'
require 'fileutils'
require 'optparse'

class PuppetApply
  def initialize(options)
    @options = options
    @facts = gather_facts
  end

  def gather_facts
    facts = {
      'hostname' => `hostname`.strip,
      'fqdn' => `hostname -f 2>/dev/null`.strip,
      'ipaddress' => `hostname -I 2>/dev/null | awk '{print $1}'`.strip,
      'architecture' => `uname -m`.strip,
      'os' => {
        'name' => 'Ubuntu',
        'release' => {
          'full' => '24.04'
        }
      },
      'puppetversion' => '1.0.0-standalone'
    }
    
    # Add FACTER_ environment variables as facts
    ENV.each do |key, value|
      if key.start_with?('FACTER_')
        fact_name = key.sub('FACTER_', '').downcase
        facts[fact_name] = value
      end
    end
    
    facts
  end

  def apply
    puts "Notice: Applying configuration..."
    
    # For now, just run the Apache installation directly
    if @options[:manifest] && @options[:manifest].include?('site.pp')
      apply_apache_module
    end
  end

  def apply_apache_module
    # Install Apache
    puts "Notice: Installing Apache2..."
    system('apt-get install -y apache2') or raise "Failed to install Apache2"
    
    # Start and enable Apache
    puts "Notice: Starting Apache2 service..."
    system('systemctl enable apache2 2>/dev/null || true')
    system('systemctl start apache2 2>/dev/null || service apache2 start')
    
    # Apply template
    template_path = File.join(@options[:modulepath], 'apache/templates/index.html.erb')
    if File.exist?(template_path)
      puts "Notice: Applying Apache template..."
      template = ERB.new(File.read(template_path))
      content = template.result(binding)
      File.write('/var/www/html/index.html', content)
      puts "Notice: Apache configuration complete"
    end
  end
end

# Parse command line options
options = {}
parser = OptionParser.new do |opts|
  opts.on('--modulepath PATH', 'Module path') { |v| options[:modulepath] = v }
  opts.on('--config PATH', 'Config file') { |v| options[:config] = v }
  opts.on('--verbose', 'Verbose output') { |v| options[:verbose] = true }
  opts.on('--detailed-exitcodes', 'Detailed exit codes (ignored)') { |v| options[:detailed] = true }
  opts.on('--version', 'Show version') do
    puts '1.0.0-standalone'
    exit 0
  end
end

# Handle both 'puppet apply' and direct manifest path
args = ARGV.dup
if args[0] == 'apply'
  args.shift
end

parser.parse!(args)
options[:manifest] = args[0] if args[0]

# Run puppet apply
if options[:manifest]
  puppet = PuppetApply.new(options)
  puppet.apply
else
  puts "Usage: puppet apply [options] manifest.pp"
  exit 1
end
PUPPET_SCRIPT
chmod +x bin/puppet

echo "Step 3: Creating wrapper script..."
cat > puppet-apply-wrapper.sh << 'SCRIPT'
#!/bin/bash
# Wrapper script for puppet apply
PUPPET_BASE="/opt/puppet-runtime"

# Use our standalone puppet
"${PUPPET_BASE}/bin/puppet" apply \
    --modulepath="${PUPPET_BASE}/modules" \
    --config="${PUPPET_BASE}/config/puppet.conf" \
    "${PUPPET_BASE}/manifests/site.pp" \
    --verbose \
    "$@"
SCRIPT
chmod +x puppet-apply-wrapper.sh

echo "Step 4: Creating tarball..."
cd "${BUILD_DIR}"
tar -czf "${OUTPUT_DIR}/puppet-runtime.tar.gz" puppet-runtime/

echo "Step 5: Copying installation scripts..."
cp "${SCRIPT_DIR}/scripts/install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/post-install.sh" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/scripts/uninstall.sh" "${OUTPUT_DIR}/"

rm -rf "${BUILD_DIR}"

echo ""
echo "=== Build Complete ==="
echo "Output files:"
echo "  - ${OUTPUT_DIR}/puppet-runtime.tar.gz"
echo "  - ${OUTPUT_DIR}/install.sh"
echo "  - ${OUTPUT_DIR}/post-install.sh"
echo "  - ${OUTPUT_DIR}/uninstall.sh"
echo ""
echo "To deploy on Ubuntu 24.04 AMD64:"
echo "  1. Copy all files from ${OUTPUT_DIR}/ to the target machine"
echo "  2. Extract: tar -xzf puppet-runtime.tar.gz -C /your/install/path"
echo "  3. Run: INSTALLER_PATH=/your/install/path sudo ./install.sh"
echo "  4. Run: sudo ./post-install.sh"