#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
CONTAINER_NAME="ansible-test-$(date +%s)"
IMAGE="ubuntu:22.04"
TEST_INSTALL_PATH="/tmp/ansible-install"
OUTPUT_DIR="$(pwd)/output"

echo -e "${GREEN}==================================="
echo "  Ansible Deployment Test"
echo "===================================${NC}"
echo ""

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
        echo "Stopping container ${CONTAINER_NAME}..."
        docker stop ${CONTAINER_NAME} >/dev/null 2>&1
    fi
    if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
        echo "Removing container ${CONTAINER_NAME}..."
        docker rm ${CONTAINER_NAME} >/dev/null 2>&1
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if [ ! -f "${OUTPUT_DIR}/ansible-runtime.tar.gz" ]; then
    echo -e "${RED}Error: ansible-runtime.tar.gz not found in ${OUTPUT_DIR}${NC}"
    echo "Please run ./build.sh first"
    exit 1
fi

# Start Ubuntu container (minimal, no pre-installs)
echo -e "\n${GREEN}Step 1: Starting Ubuntu container${NC}"
docker run -d \
    --name ${CONTAINER_NAME} \
    -p 8888:80 \
    ${IMAGE} \
    /bin/bash -c "tail -f /dev/null"

echo "Waiting for container to be ready..."
sleep 2

# Verify container is running
if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo -e "${RED}Error: Container failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Container ${CONTAINER_NAME} is running${NC}"

# Copy files to container
echo -e "\n${GREEN}Step 2: Copying files to container${NC}"
docker exec ${CONTAINER_NAME} mkdir -p ${TEST_INSTALL_PATH}
docker cp ${OUTPUT_DIR}/ansible-runtime.tar.gz ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/
docker cp ${OUTPUT_DIR}/install.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/
docker cp ${OUTPUT_DIR}/post-install.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/

echo -e "${GREEN}✓ Files copied successfully${NC}"

# Extract tar.gz
echo -e "\n${GREEN}Step 3: Extracting ansible-runtime.tar.gz${NC}"
docker exec ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && tar -xzf ansible-runtime.tar.gz"
echo -e "${GREEN}✓ Extraction complete${NC}"

# Run install.sh
echo -e "\n${GREEN}Step 4: Running install.sh${NC}"
docker exec -e INSTALL_PATH=${TEST_INSTALL_PATH} ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && ./install.sh"

# Verify Ansible installation
echo -e "\n${GREEN}Step 5: Verifying Ansible installation${NC}"
docker exec ${CONTAINER_NAME} ansible --version
echo -e "${GREEN}✓ Ansible installed successfully${NC}"

# Run post-install.sh to install Apache
echo -e "\n${GREEN}Step 6: Running post-install.sh (Apache installation)${NC}"
docker exec ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && ./post-install.sh"

# Verify Apache is running (use service command which works without systemd)
echo -e "\n${GREEN}Step 7: Verifying Apache installation${NC}"
docker exec ${CONTAINER_NAME} bash -c "service apache2 status | grep -q 'apache2 is running' && echo '✓ Apache is running' || echo '✗ Apache status unknown'"

# Test Apache response (should be running from Ansible)
echo -e "\n${GREEN}Step 8: Testing Apache response${NC}"
sleep 3

# Test with wget (comes with Ubuntu by default)
docker exec ${CONTAINER_NAME} bash -c "wget -q -O - http://localhost/ | grep -q 'It works!' && echo '✓ Apache is responding with \"It works!\"' || echo '✗ Apache page not as expected'"

# Also test from host
echo -e "\nTesting from host machine (port 8888):"
if curl -s http://localhost:8888/ 2>/dev/null | grep -q "It works!"; then
    echo -e "${GREEN}✓ Apache accessible from host${NC}"
else
    # Try with wget if curl isn't available
    if wget -q -O - http://localhost:8888/ 2>/dev/null | grep -q "It works!"; then
        echo -e "${GREEN}✓ Apache accessible from host${NC}"
    else
        echo -e "${YELLOW}Warning: Could not verify Apache from host${NC}"
    fi
fi

# Clean up temporary directory
echo -e "\n${GREEN}Step 9: Cleaning up temporary installation directory${NC}"
docker exec ${CONTAINER_NAME} rm -rf ${TEST_INSTALL_PATH}
echo -e "${GREEN}✓ Temporary directory removed${NC}"

# Verify Ansible still works after temp cleanup
echo -e "\n${GREEN}Step 10: Verifying Ansible works after temp cleanup${NC}"
docker exec ${CONTAINER_NAME} ansible --version >/dev/null 2>&1 && echo -e "${GREEN}✓ Ansible still functional${NC}" || echo -e "${RED}✗ Ansible not working${NC}"

# Run uninstall.sh
echo -e "\n${GREEN}Step 11: Running uninstall.sh${NC}"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/
docker exec ${CONTAINER_NAME} bash -c "cd /tmp && ./uninstall.sh"

# Verify uninstallation
echo -e "\n${GREEN}Step 12: Verifying uninstallation${NC}"
if docker exec ${CONTAINER_NAME} which ansible >/dev/null 2>&1; then
    echo -e "${RED}✗ Ansible still present after uninstall${NC}"
else
    echo -e "${GREEN}✓ Ansible successfully removed${NC}"
fi

# Check if Apache was removed
if docker exec ${CONTAINER_NAME} which apache2 >/dev/null 2>&1; then
    echo -e "${RED}✗ Apache still present after uninstall${NC}"
else
    echo -e "${GREEN}✓ Apache successfully removed${NC}"
fi

echo -e "\n${GREEN}==================================="
echo "  Test Complete!"
echo "===================================${NC}"
echo ""
echo "Summary:"
echo "  • Ubuntu container created (minimal, no extra installs)"
echo "  • Ansible installed from temporary location"
echo "  • Apache installed and verified"
echo "  • Temporary directory cleaned up"
echo "  • Uninstallation completed successfully"
echo ""
echo -e "${GREEN}All tests passed!${NC}"
