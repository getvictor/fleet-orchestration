#!/bin/bash

set -e

# Quick test that pre-installs Python to save time

echo "Quick Ansible Deployment Test"
echo "=============================="

CONTAINER_NAME="ansible-quick-test"
OUTPUT_DIR="$(pwd)/output"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    docker stop ${CONTAINER_NAME} 2>/dev/null || true
    docker rm ${CONTAINER_NAME} 2>/dev/null || true
}

trap cleanup EXIT

# Remove any existing container
cleanup

echo "1. Starting Ubuntu container..."
docker run -d \
    --name ${CONTAINER_NAME} \
    -p 9999:80 \
    ubuntu:22.04 \
    /bin/bash -c "tail -f /dev/null"

echo "   Installing Python and wget in container..."
docker exec ${CONTAINER_NAME} bash -c "apt-get update && apt-get install -y python3 python3-pip python3-venv wget"
echo "   Dependencies installed successfully"

echo "2. Copying files..."
docker exec ${CONTAINER_NAME} mkdir -p /tmp/test
docker cp ${OUTPUT_DIR}/ansible-runtime.tar.gz ${CONTAINER_NAME}:/tmp/test/
docker cp ${OUTPUT_DIR}/install.sh ${CONTAINER_NAME}:/tmp/test/
docker cp ${OUTPUT_DIR}/post-install.sh ${CONTAINER_NAME}:/tmp/test/
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/test/

echo "3. Extracting archive..."
docker exec ${CONTAINER_NAME} bash -c "cd /tmp/test && tar -xzf ansible-runtime.tar.gz"

echo "4. Running install.sh..."
docker exec -e INSTALL_PATH=/tmp/test ${CONTAINER_NAME} bash -c "cd /tmp/test && ./install.sh"

echo "5. Testing ansible command..."
docker exec ${CONTAINER_NAME} ansible --version

echo "6. Running post-install.sh (Apache)..."
docker exec ${CONTAINER_NAME} bash -c "cd /tmp/test && ./post-install.sh"

echo "7. Testing Apache (should be already running from Ansible)..."
sleep 2
docker exec ${CONTAINER_NAME} bash -c "wget -q -O - http://localhost/ 2>/dev/null | grep 'It works!' && echo '   ✓ Apache is working!' || echo '   ✗ Apache test failed'"

echo "8. Cleaning temp directory..."
docker exec ${CONTAINER_NAME} rm -rf /tmp/test

echo "9. Verifying Ansible still works..."
docker exec ${CONTAINER_NAME} ansible --version >/dev/null && echo "✓ Ansible still works" || echo "✗ Ansible broken"

echo "10. Running uninstall.sh..."
docker cp ${OUTPUT_DIR}/uninstall.sh ${CONTAINER_NAME}:/tmp/
docker exec ${CONTAINER_NAME} bash -c "cd /tmp && ./uninstall.sh"

echo "11. Verifying uninstall..."
docker exec ${CONTAINER_NAME} which ansible 2>/dev/null && echo "✗ Ansible still present" || echo "✓ Ansible removed"

echo ""
echo "Quick test complete!"