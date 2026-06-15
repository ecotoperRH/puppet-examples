#!/bin/bash
#
# Application Health Check Script
# Managed by Ansible - DO NOT EDIT MANUALLY
#

APP_PORT=${1:-8000}
HEALTH_ENDPOINT=${2:-"/health"}
TIMEOUT=${3:-5}

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is not installed. Please install curl to use this script."
    exit 1
fi

# Perform health check
echo "Checking application health on port $APP_PORT..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT http://localhost:$APP_PORT$HEALTH_ENDPOINT)

if [ "$RESPONSE" == "200" ]; then
    echo "Health check passed: HTTP $RESPONSE"
    exit 0
else
    echo "Health check failed: HTTP $RESPONSE"
    exit 1
fi