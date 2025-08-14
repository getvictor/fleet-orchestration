#!/bin/bash

# Stop and remove any running Chef test containers

echo "Stopping Chef test containers..."

# Stop all containers with names starting with "chef-test" or "chef-quick-test"
docker ps -q -f name=chef-test | xargs -r docker stop 2>/dev/null
docker ps -q -f name=chef-quick-test | xargs -r docker stop 2>/dev/null

echo "Removing Chef test containers..."

# Remove all containers (including stopped ones)
docker ps -aq -f name=chef-test | xargs -r docker rm 2>/dev/null
docker ps -aq -f name=chef-quick-test | xargs -r docker rm 2>/dev/null

echo "✓ All Chef test containers stopped and removed"

# Show any remaining docker containers
REMAINING=$(docker ps -a -f name=chef --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2)
if [ ! -z "$REMAINING" ]; then
    echo ""
    echo "Note: Found other Chef-related containers:"
    echo "$REMAINING"
fi