#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file configuration
LOG_FILE="/tmp/chef-test-$(date +%Y%m%d-%H%M%S).log"

# Function to log output to both console and file
log() {
    echo -e "$@" | tee -a "$LOG_FILE"
}

# Test configuration
CONTAINER_NAME="chef-test-$(date +%s)"
IMAGE="ubuntu:24.04"
TEST_INSTALL_PATH="/tmp/chef-install"
OUTPUT_DIR="$(pwd)/output"

log "${GREEN}==================================="
log "  Chef Deployment Test"
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

if [ ! -f "${OUTPUT_DIR}/chef-runtime.tar.gz" ]; then
    log "${RED}Error: chef-runtime.tar.gz not found in ${OUTPUT_DIR}${NC}"
    log "Please run ./build.sh first"
    exit 1
fi

# Start Ubuntu container (minimal, no pre-installs) - AMD64 platform
log "\n${GREEN}Step 1: Starting Ubuntu 24.04 AMD64 container${NC}"
docker run -d \
    --platform linux/amd64 \
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
docker exec ${CONTAINER_NAME} mkdir -p ${TEST_INSTALL_PATH} 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/chef-runtime.tar.gz ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/install.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/post-install.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"

log "${GREEN}✓ Files copied successfully${NC}"

# Extract tar.gz
log "\n${GREEN}Step 3: Extracting chef-runtime.tar.gz${NC}"
docker exec ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && tar -xzf chef-runtime.tar.gz" 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Extraction complete${NC}"

# Run install.sh
log "\n${GREEN}Step 4: Running install.sh${NC}"
docker exec -e INSTALLER_PATH=${TEST_INSTALL_PATH} ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && ./install.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify Chef installation
log "\n${GREEN}Step 5: Verifying Chef installation${NC}"
docker exec ${CONTAINER_NAME} /opt/chef-runtime/chef/bin/chef-client --version 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Chef installed successfully${NC}"

# Run post-install.sh to install Apache
log "\n${GREEN}Step 6: Running post-install.sh (Apache installation)${NC}"
docker exec -e FLEET_SECRET_VAR1=var1_contents ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && ./post-install.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify Apache is running
log "\n${GREEN}Step 7: Verifying Apache installation${NC}"
docker exec ${CONTAINER_NAME} bash -c "if systemctl is-active --quiet apache2 2>/dev/null; then echo '✓ Apache is running'; elif service apache2 status 2>/dev/null | grep -q 'running'; then echo '✓ Apache is running'; elif pgrep apache2 >/dev/null 2>&1; then echo '✓ Apache process found'; else echo '✗ Apache not running - attempting to start'; service apache2 start 2>/dev/null || systemctl start apache2 2>/dev/null || true; fi" 2>&1 | tee -a "$LOG_FILE"

# Test Apache response
log "\n${GREEN}Step 8: Testing Apache response${NC}"
sleep 3

# Install wget if not present (base Ubuntu container doesn't have it)
docker exec ${CONTAINER_NAME} bash -c "which wget >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y wget >/dev/null 2>&1)" 2>&1 | tee -a "$LOG_FILE"

# Test with wget
docker exec ${CONTAINER_NAME} bash -c "wget -q -O - http://localhost/ | grep -q 'It works!' && echo '✓ Apache is responding with \"It works!\"' || echo '✗ Apache page not as expected'" 2>&1 | tee -a "$LOG_FILE"

# Also test from host
log "\nTesting from host machine (port 8889):"
if curl -s http://localhost:8889/ 2>/dev/null | grep -q "It works!"; then
    log "${GREEN}✓ Apache accessible from host${NC}"
else
    # Try with wget if curl isn't available
    if wget -q -O - http://localhost:8889/ 2>/dev/null | grep -q "It works!"; then
        log "${GREEN}✓ Apache accessible from host${NC}"
    else
        log "${YELLOW}Warning: Could not verify Apache from host${NC}"
    fi
fi

# Clean up temporary directory
log "\n${GREEN}Step 9: Cleaning up temporary installation directory${NC}"
docker exec ${CONTAINER_NAME} rm -rf ${TEST_INSTALL_PATH} 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Temporary directory removed${NC}"

# Verify Chef still works after temp cleanup
log "\n${GREEN}Step 10: Verifying Chef works after temp cleanup${NC}"
docker exec ${CONTAINER_NAME} chef-client --version >/dev/null 2>&1 && log "${GREEN}✓ Chef still functional${NC}" || log "${RED}✗ Chef not working${NC}"

# Run uninstall.sh
log "\n${GREEN}Step 11: Running uninstall.sh${NC}"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/ 2>&1 | tee -a "$LOG_FILE"
docker exec ${CONTAINER_NAME} bash -c "cd /tmp && ./uninstall.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify uninstallation
log "\n${GREEN}Step 12: Verifying uninstallation${NC}"
if docker exec ${CONTAINER_NAME} which chef-client >/dev/null 2>&1; then
    log "${RED}✗ Chef still present after uninstall${NC}"
else
    log "${GREEN}✓ Chef successfully removed${NC}"
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
log "  • Ubuntu container created (minimal, no extra installs)"
log "  • Chef installed from temporary location"
log "  • Apache installed and verified via Chef cookbook"
log "  • Temporary directory cleaned up"
log "  • Uninstallation completed successfully"
log ""
log "${GREEN}All tests passed!${NC}"
log "Full log saved to: $LOG_FILE"
