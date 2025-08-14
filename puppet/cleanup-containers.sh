#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}==================================="
echo "  Container Cleanup Script"
echo "===================================${NC}"
echo ""

# Function to cleanup containers by pattern
cleanup_containers() {
    local pattern=$1
    local description=$2
    
    echo -e "${YELLOW}Cleaning up ${description}...${NC}"
    
    # Stop running containers
    local running=$(docker ps -q --filter "name=${pattern}")
    if [ -n "$running" ]; then
        echo "Stopping running containers..."
        echo "$running" | xargs docker stop
        echo -e "${GREEN}✓ Stopped running containers${NC}"
    else
        echo "No running containers found"
    fi
    
    # Remove all containers (including stopped)
    local all=$(docker ps -aq --filter "name=${pattern}")
    if [ -n "$all" ]; then
        echo "Removing containers..."
        echo "$all" | xargs docker rm -f
        echo -e "${GREEN}✓ Removed containers${NC}"
    else
        echo "No containers to remove"
    fi
    
    echo ""
}

# Clean up Puppet test containers
cleanup_containers "puppet-test-" "Puppet test containers"

# Clean up Ansible test containers
cleanup_containers "ansible-test-" "Ansible test containers"

# Clean up Chef test containers (if any)
cleanup_containers "chef-test-" "Chef test containers"

# Show current Docker status
echo -e "${GREEN}Current Docker containers:${NC}"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo -e "${GREEN}==================================="
echo "  Cleanup Complete!"
echo "===================================${NC}"