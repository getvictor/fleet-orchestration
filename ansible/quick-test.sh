#!/bin/bash

set -e

# Quick test that pre-installs Python to save time

LOG_FILE="/tmp/quick-test-$(date +%Y%m%d-%H%M%S).log"

# Function to log output to both console and file
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

log "Quick Ansible Deployment Test"
log "=============================="
log "Log file: $LOG_FILE"
log ""

CONTAINER_NAME="ansible-quick-test"
OUTPUT_DIR="$(pwd)/output"

# Cleanup function
cleanup() {
    log "Cleaning up..."
    docker stop ${CONTAINER_NAME} 2>/dev/null || true
    docker rm ${CONTAINER_NAME} 2>/dev/null || true
}

trap cleanup EXIT

# Remove any existing container
cleanup

log "1. Starting Ubuntu container..."
docker run -d \
    --name ${CONTAINER_NAME} \
    -p 9999:80 \
    ubuntu:22.04 \
    /bin/bash -c "tail -f /dev/null" 2>&1 | tee -a "$LOG_FILE"

log "   Installing Python and wget in container..."
docker exec ${CONTAINER_NAME} bash -c "apt-get update && apt-get install -y python3 python3-pip python3-venv wget" 2>&1 | tee -a "$LOG_FILE"
log "   Dependencies installed successfully"

log "2. Copying files..."
docker exec ${CONTAINER_NAME} mkdir -p /tmp/test 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/ansible-runtime.tar.gz ${CONTAINER_NAME}:/tmp/test/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/install.sh ${CONTAINER_NAME}:/tmp/test/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/post-install.sh ${CONTAINER_NAME}:/tmp/test/ 2>&1 | tee -a "$LOG_FILE"
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/test/ 2>&1 | tee -a "$LOG_FILE"

log "3. Extracting archive..."
docker exec ${CONTAINER_NAME} bash -c "cd /tmp/test && tar -xzf ansible-runtime.tar.gz" 2>&1 | tee -a "$LOG_FILE"

log "4. Running install.sh..."
docker exec -e INSTALL_PATH=/tmp/test ${CONTAINER_NAME} bash -c "cd /tmp/test && ./install.sh" 2>&1 | tee -a "$LOG_FILE"

log "5. Testing ansible command..."
docker exec ${CONTAINER_NAME} ansible --version 2>&1 | tee -a "$LOG_FILE"

log "6. Running post-install.sh (Apache)..."
docker exec ${CONTAINER_NAME} bash -c "cd /tmp/test && ./post-install.sh" 2>&1 | tee -a "$LOG_FILE"

log "7. Testing Apache (should be already running from Ansible)..."
sleep 2
docker exec ${CONTAINER_NAME} bash -c "wget -q -O - http://localhost/ 2>/dev/null | grep 'It works!' && echo '   ✓ Apache is working!' || echo '   ✗ Apache test failed'" 2>&1 | tee -a "$LOG_FILE"

log "8. Cleaning temp directory..."
docker exec ${CONTAINER_NAME} rm -rf /tmp/test 2>&1 | tee -a "$LOG_FILE"

log "9. Verifying Ansible still works..."
docker exec ${CONTAINER_NAME} ansible --version >/dev/null 2>&1 && log "✓ Ansible still works" || log "✗ Ansible broken"

log "10. Running uninstall.sh..."
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/ 2>&1 | tee -a "$LOG_FILE"
docker exec ${CONTAINER_NAME} bash -c "cd /tmp && ./uninstall.sh" 2>&1 | tee -a "$LOG_FILE"

log "11. Verifying uninstall..."
docker exec ${CONTAINER_NAME} which ansible 2>/dev/null && log "✗ Ansible still present" || log "✓ Ansible removed"

log ""
log "Quick test complete!"
log "Full log saved to: $LOG_FILE"