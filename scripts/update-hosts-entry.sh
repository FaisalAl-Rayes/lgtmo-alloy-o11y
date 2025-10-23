#!/bin/bash

# Update /etc/hosts entry for multi-cluster.local
# This script adds or updates the IP address for multi-cluster.local

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

HOSTNAME="multi-cluster.local"
HOSTS_FILE="/etc/hosts"

# Get the IP address from en0 interface
echo -e "${YELLOW}Getting IP address from en0...${NC}"
IP_ADDRESS=$(ifconfig en0 | awk '/inet / {print $2}')

if [ -z "$IP_ADDRESS" ]; then
    echo -e "${RED}✗ Failed to get IP address from en0${NC}"
    echo "Make sure en0 interface is active"
    exit 1
fi

echo "IP Address: $IP_ADDRESS"
echo "Hostname: $HOSTNAME"
echo ""

# Check if hostname already exists in /etc/hosts
if grep -q "[[:space:]]${HOSTNAME}$" "$HOSTS_FILE" 2>/dev/null; then
    echo -e "${YELLOW}Entry for ${HOSTNAME} found in ${HOSTS_FILE}${NC}"
    
    # Get the current IP
    CURRENT_IP=$(grep "[[:space:]]${HOSTNAME}$" "$HOSTS_FILE" | awk '{print $1}')
    echo "Current IP: $CURRENT_IP"
    
    if [ "$CURRENT_IP" = "$IP_ADDRESS" ]; then
        echo -e "${GREEN}✓ IP address is already up to date${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Updating IP address...${NC}"
    # Create backup
    sudo cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Replace the line with new IP
    sudo sed -i '' "s/^.*[[:space:]]${HOSTNAME}$/${IP_ADDRESS} ${HOSTNAME}/" "$HOSTS_FILE"
    
    echo -e "${GREEN}✓ Updated ${HOSTNAME} from ${CURRENT_IP} to ${IP_ADDRESS}${NC}"
else
    echo -e "${YELLOW}Entry for ${HOSTNAME} not found, adding new entry...${NC}"
    
    # Create backup
    sudo cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add new entry
    echo "${IP_ADDRESS} ${HOSTNAME}" | sudo tee -a "$HOSTS_FILE" > /dev/null
    
    echo -e "${GREEN}✓ Added ${IP_ADDRESS} ${HOSTNAME} to ${HOSTS_FILE}${NC}"
fi

echo ""
echo "Verifying entry:"
grep "${HOSTNAME}" "$HOSTS_FILE"

