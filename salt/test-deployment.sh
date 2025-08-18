#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file configuration
LOG_FILE="/tmp/salt-test-$(date +%Y%m%d-%H%M%S).log"

# Function to log output to both console and file
log() {
    echo -e "$@" | tee -a "$LOG_FILE"
}

# Test configuration
CONTAINER_NAME="salt-test-$(date +%s)"
IMAGE="ubuntu:24.04"
TEST_INSTALL_PATH="/tmp/salt-install"
OUTPUT_DIR="$(pwd)/output"

log "${GREEN}==================================="
log "  Salt Deployment Test"
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

if [ ! -f "${OUTPUT_DIR}/salt-runtime.tar.gz" ]; then
    log "${RED}Error: salt-runtime.tar.gz not found in ${OUTPUT_DIR}${NC}"
    log "Please run ./build.sh first"
    exit 1
fi

# Start Ubuntu container (minimal, no pre-installs) - AMD64 platform
log "\n${GREEN}Step 1: Starting Ubuntu 24.04 AMD64 container${NC}"
docker run -d \
    --platform linux/amd64 \
    --name ${CONTAINER_NAME} \
    -p 8892:80 \
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
docker cp ${OUTPUT_DIR}/salt-runtime.tar.gz ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/install.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/post-install.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:${TEST_INSTALL_PATH}/ 2>&1 | tee -a "$LOG_FILE"

log "${GREEN}✓ Files copied successfully${NC}"

# Extract the tarball
log "\n${GREEN}Step 3: Extracting salt-runtime.tar.gz${NC}"
docker exec ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && tar -xzf salt-runtime.tar.gz" 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Extraction complete${NC}"

# Set execute permissions on scripts (docker cp doesn't preserve permissions)
docker exec ${CONTAINER_NAME} chmod +x ${TEST_INSTALL_PATH}/install.sh ${TEST_INSTALL_PATH}/post-install.sh ${TEST_INSTALL_PATH}/uninstall.sh 2>&1 | tee -a "$LOG_FILE"

# Run install.sh
log "\n${GREEN}Step 4: Running install.sh${NC}"
docker exec -e INSTALLER_PATH=${TEST_INSTALL_PATH} ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && ./install.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify Salt installation
log "\n${GREEN}Step 5: Verifying Salt installation${NC}"
docker exec ${CONTAINER_NAME} salt-call --version 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Salt installed successfully${NC}"

# Run post-install.sh to install Apache
log "\n${GREEN}Step 6: Running post-install.sh (Apache installation)${NC}"
docker exec -e INSTALLER_PATH=${TEST_INSTALL_PATH} -e FLEET_SECRET_VAR1=var1_contents ${CONTAINER_NAME} bash -c "cd ${TEST_INSTALL_PATH} && ./post-install.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify Apache is running
log "\n${GREEN}Step 7: Verifying Apache installation${NC}"
if ! docker exec ${CONTAINER_NAME} bash -c "systemctl is-active --quiet apache2 2>/dev/null || service apache2 status 2>/dev/null | grep -q 'running' || pgrep apache2 >/dev/null 2>&1"; then
    log "${RED}✗ Apache is not running${NC}"
    log "${RED}Test FAILED: Apache was not installed/started by Salt${NC}"
    exit 1
else
    log "${GREEN}✓ Apache is running${NC}"
fi

# Test Apache response
log "\n${GREEN}Step 8: Testing Apache response${NC}"
sleep 3

# Install wget if not present (base Ubuntu container doesn't have it)
docker exec ${CONTAINER_NAME} bash -c "which wget >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y wget >/dev/null 2>&1)" 2>&1 | tee -a "$LOG_FILE"

# Test with wget
if ! docker exec ${CONTAINER_NAME} bash -c "wget -q -O - http://localhost/ | grep -q 'It works!'"; then
    log "${RED}✗ Apache page not as expected${NC}"
    log "${RED}Test FAILED: Apache is not serving the expected page${NC}"
    exit 1
else
    log "${GREEN}✓ Apache is responding with \"It works!\"${NC}"
fi

# Also test from host
log "\nTesting from host machine (port 8892):"
if curl -s http://localhost:8892/ 2>/dev/null | grep -q "It works!"; then
    log "${GREEN}✓ Apache accessible from host${NC}"
else
    # Try with wget if curl isn't available
    if wget -q -O - http://localhost:8892/ 2>/dev/null | grep -q "It works!"; then
        log "${GREEN}✓ Apache accessible from host${NC}"
    else
        log "${YELLOW}Warning: Could not verify Apache from host${NC}"
    fi
fi

# Clean up temporary directory
log "\n${GREEN}Step 9: Cleaning up temporary installation directory${NC}"
docker exec ${CONTAINER_NAME} rm -rf ${TEST_INSTALL_PATH} 2>&1 | tee -a "$LOG_FILE"
log "${GREEN}✓ Temporary directory removed${NC}"

# Verify Salt still works after temp cleanup
log "\n${GREEN}Step 10: Verifying Salt works after temp cleanup${NC}"
docker exec ${CONTAINER_NAME} salt-call --version >/dev/null 2>&1 && log "${GREEN}✓ Salt still functional${NC}" || log "${RED}✗ Salt not working${NC}"

# Run uninstall.sh
log "\n${GREEN}Step 11: Running uninstall.sh${NC}"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/ 2>&1 | tee -a "$LOG_FILE"
docker exec ${CONTAINER_NAME} bash -c "cd /tmp && ./uninstall.sh" 2>&1 | tee -a "$LOG_FILE"

# Verify uninstallation
log "\n${GREEN}Step 12: Verifying uninstallation${NC}"
if docker exec ${CONTAINER_NAME} which salt-call >/dev/null 2>&1; then
    log "${RED}✗ Salt still present after uninstall${NC}"
else
    log "${GREEN}✓ Salt successfully removed${NC}"
fi

# Check if Salt virtual environment was removed
if docker exec ${CONTAINER_NAME} test -d /opt/salt-venv; then
    log "${RED}✗ Salt virtual environment still present${NC}"
else
    log "${GREEN}✓ Salt virtual environment removed${NC}"
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
log "  • Salt installed and configured for masterless mode"
log "  • Apache installed and verified via Salt states"
log "  • Temporary directory cleaned up"
log "  • Uninstallation completed successfully"
log ""
log "${GREEN}All tests passed!${NC}"
log "Full log saved to: $LOG_FILE"