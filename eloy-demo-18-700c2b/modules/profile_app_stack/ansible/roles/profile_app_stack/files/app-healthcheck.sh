#!/bin/bash
# Application health check script

# Default values
APP_HOST=${APP_HOST:-"localhost"}
APP_PORT=${APP_PORT:-8000}
HEALTH_ENDPOINT=${HEALTH_ENDPOINT:-"/health"}
TIMEOUT=${TIMEOUT:-5}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--host)
      APP_HOST="$2"
      shift 2
      ;;
    -p|--port)
      APP_PORT="$2"
      shift 2
      ;;
    -e|--endpoint)
      HEALTH_ENDPOINT="$2"
      shift 2
      ;;
    -t|--timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [-h|--host hostname] [-p|--port port] [-e|--endpoint path] [-t|--timeout seconds]"
      exit 1
      ;;
  esac
done

# Construct the URL
URL="http://${APP_HOST}:${APP_PORT}${HEALTH_ENDPOINT}"

echo "Checking application health at: ${URL}"

# Make the request with timeout
response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout ${TIMEOUT} ${URL})

# Check the response
if [ "$response" == "200" ]; then
  echo "Health check passed: HTTP ${response}"
  exit 0
else
  echo "Health check failed: HTTP ${response}"
  exit 1
fi