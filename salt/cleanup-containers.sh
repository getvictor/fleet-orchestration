#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Stopping and removing Salt test containers...${NC}"

# Find and stop/remove all salt-test containers
containers=$(docker ps -aq --filter "name=salt-test-")

if [ -z "$containers" ]; then
    echo -e "${GREEN}No Salt test containers found${NC}"
else
    echo "Found $(echo "$containers" | wc -l) Salt test container(s)"
    
    # Stop running containers
    running=$(docker ps -q --filter "name=salt-test-")
    if [ ! -z "$running" ]; then
        echo "Stopping running containers..."
        docker stop $running
    fi
    
    # Remove all containers
    echo "Removing containers..."
    docker rm $containers
    
    echo -e "${GREEN}✓ All Salt test containers removed${NC}"
fi

echo ""
echo "Current Docker containers:"
docker ps -a --filter "name=salt-test-" --format "table {{.Names}}\t{{.Status}}"