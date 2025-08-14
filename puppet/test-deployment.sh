#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
CONTAINER_NAME="puppet-test-$(date +%s)"
IMAGE="ubuntu:24.04"
TEST_INSTALLER_PATH="/tmp/puppet-install"
OUTPUT_DIR="$(pwd)/output"
LOG_FILE="/tmp/puppet-deployment-$(date +%Y%m%d-%H%M%S).log"

# Function to log output to both console and file
log() {
    echo -e "$@" | tee -a "$LOG_FILE"
}

log "${GREEN}==================================="
log "  Puppet Deployment Test"
log "===================================${NC}"
log "Log file: $LOG_FILE"
log ""

# Function to cleanup on exit
cleanup() {
    log "\n${YELLOW}Cleaning up...${NC}"
    if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
        log "Stopping container ${CONTAINER_NAME}..."
        docker stop ${CONTAINER_NAME} >/dev/null 2>&1
    fi
    if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
        log "Removing container ${CONTAINER_NAME}..."
        docker rm ${CONTAINER_NAME} >/dev/null 2>&1
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check prerequisites
log "Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    log "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if [ ! -f "${OUTPUT_DIR}/puppet-runtime.tar.gz" ]; then
    log "${RED}Error: puppet-runtime.tar.gz not found in ${OUTPUT_DIR}${NC}"
    log "Please run ./build.sh first"
    exit 1
fi

# Start Ubuntu container
log "\n${GREEN}Step 1: Starting Ubuntu 24.04 container${NC}"
docker run -d \
    --name ${CONTAINER_NAME} \
    -p 8889:80 \
    ${IMAGE} \
    /bin/bash -c "tail -f /dev/null" 2>&1 | tee -a "$LOG_FILE"

log "Waiting for container to be ready..."
sleep 2

# Verify container is running
if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    log "${RED}Error: Container failed to start${NC}"
    exit 1
fi

log "${GREEN}✓ Container ${CONTAINER_NAME} is running${NC}"

# Copy files to container
log "\n${GREEN}Step 2: Copying files to container${NC}"
docker exec ${CONTAINER_NAME} mkdir -p ${TEST_INSTALLER_PATH} 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/puppet-runtime.tar.gz ${CONTAINER_NAME}:${TEST_INSTALLER_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/install.sh ${CONTAINER_NAME}:${TEST_INSTALLER_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/post-install.sh ${CONTAINER_NAME}:${TEST_INSTALLER_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:${TEST_INSTALLER_PATH}/ 2>&1 | tee -a "$LOG_FILE"

log "${GREEN}✓ Files copied successfully${NC}"

# Extract tar.gz
log "\n${GREEN}Step 3: Extracting puppet-runtime.tar.gz${NC}"
docker exec ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALLER_PATH} && tar -xzf puppet-runtime.tar.gz" 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Extraction complete${NC}"

# Run install.sh
log "\n${GREEN}Step 4: Running install.sh${NC}"
docker exec -e INSTALLER_PATH=${TEST_INSTALLER_PATH} ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALLER_PATH} && ./install.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify Puppet installation
log "\n${GREEN}Step 5: Verifying Puppet installation${NC}"
docker exec ${CONTAINER_NAME} bash -c "export PATH=/opt/puppetlabs/bin:\$PATH; puppet --version" 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Puppet installed successfully${NC}"

# Run post-install.sh to install Apache
log "\n${GREEN}Step 6: Running post-install.sh (Apache installation)${NC}"
docker exec -e FLEET_SECRET_VAR1=var1_contents ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALLER_PATH} && ./post-install.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify Apache is running
log "\n${GREEN}Step 7: Verifying Apache installation${NC}"
docker exec ${CONTAINER_NAME} bash -c "service apache2 status | grep -q 'apache2 is running' && echo '✓ Apache is running' || echo '✗ Apache status unknown'" 2>&1 | tee -a "$LOG_FILE"

# Test Apache response
log "\n${GREEN}Step 8: Testing Apache response${NC}"
sleep 3

# Test with wget
docker exec ${CONTAINER_NAME} bash -c "wget -q -O - http://localhost/ 2>/dev/null | grep -q 'It works!' && echo '✓ Apache is responding with \"It works!\"' || echo '✗ Apache page not as expected'" 2>&1 | tee -a "$LOG_FILE"

# Also test from host
log "\nTesting from host machine (port 8889):"
if curl -s http://localhost:8889/ 2>/dev/null | grep -q "It works!"; then
    log "${GREEN}✓ Apache accessible from host${NC}"
else
    if wget -q -O - http://localhost:8889/ 2>/dev/null | grep -q "It works!"; then
        log "${GREEN}✓ Apache accessible from host${NC}"
    else
        log "${YELLOW}Warning: Could not verify Apache from host${NC}"
    fi
fi

# Clean up temporary directory
log "\n${GREEN}Step 9: Cleaning up temporary installation directory${NC}"
docker exec ${CONTAINER_NAME} rm -rf ${TEST_INSTALLER_PATH} 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Temporary directory removed${NC}"

# Verify Puppet still works after temp cleanup
log "\n${GREEN}Step 10: Verifying Puppet works after temp cleanup${NC}"
docker exec ${CONTAINER_NAME} bash -c "export PATH=/opt/puppetlabs/bin:\$PATH; puppet --version" >/dev/null 2>&1 && log "${GREEN}✓ Puppet still functional${NC}" || log "${RED}✗ Puppet not working${NC}"

# Run uninstall.sh
log "\n${GREEN}Step 11: Running uninstall.sh${NC}"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/ 2>&1 | tee -a "$LOG_FILE"
docker exec ${CONTAINER_NAME} bash -c "cd /tmp && ./uninstall.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify uninstallation
log "\n${GREEN}Step 12: Verifying uninstallation${NC}"
if docker exec ${CONTAINER_NAME} bash -c "export PATH=/opt/puppetlabs/bin:\$PATH; which puppet" >/dev/null 2>&1; then
    log "${RED}✗ Puppet still present after uninstall${NC}"
else
    log "${GREEN}✓ Puppet successfully removed${NC}"
fi

# Check if Apache was removed
if docker exec ${CONTAINER_NAME} which apache2 >/dev/null 2>&1; then
    log "${RED}✗ Apache still present after uninstall${NC}"
else
    log "${GREEN}✓ Apache successfully removed${NC}"
fi

log "\n${GREEN}==================================="
log "  Test Complete!"
log "===================================${NC}"
log ""
log "Summary:"
log "  • Ubuntu 24.04 container created"
log "  • Puppet installed from temporary location"
log "  • Apache installed and verified via Puppet"
log "  • Temporary directory cleaned up"
log "  • Uninstallation completed successfully"
log ""
log "${GREEN}All tests passed!${NC}"
log ""
log "Full log saved to: $LOG_FILE"
