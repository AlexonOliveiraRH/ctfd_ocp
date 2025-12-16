#!/bin/bash

# CTFd OpenShift Deployment Script
# This script deploys CTFd on OpenShift 4.20.6

set -e

echo "========================================="
echo "CTFd OpenShift Deployment"
echo "========================================="

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo "Error: oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged into OpenShift. Please run 'oc login' first."
    exit 1
fi

echo ""
echo "Step 1: Creating namespace..."
oc apply -f 01-namespace.yaml

echo ""
echo "Step 2: Creating secrets..."
echo "WARNING: Please edit 02-secrets.yaml to change default passwords before deploying to production!"
read -p "Press Enter to continue or Ctrl+C to exit and edit secrets..."
oc apply -f 02-secrets.yaml

echo ""
echo "Step 3: Deploying MariaDB..."
oc apply -f 03-mariadb.yaml
echo "Waiting for MariaDB to be ready..."
oc wait --for=condition=available --timeout=300s deployment/mariadb -n ctfd

echo ""
echo "Step 4: Deploying Redis..."
oc apply -f 04-redis.yaml
echo "Waiting for Redis to be ready..."
oc wait --for=condition=available --timeout=180s deployment/redis -n ctfd

echo ""
echo "Step 5: Deploying CTFd application..."
oc apply -f 05-ctfd.yaml
echo "Waiting for CTFd to be ready..."
oc wait --for=condition=available --timeout=300s deployment/ctfd -n ctfd

echo ""
echo "Step 6: Creating OpenShift Route..."
oc apply -f 06-route.yaml

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Getting CTFd URL..."
CTFD_URL=$(oc get route ctfd -n ctfd -o jsonpath='{.spec.host}')
echo ""
echo "CTFd is now accessible at: https://$CTFD_URL"
echo ""
echo "You can check the deployment status with:"
echo "  oc get pods -n ctfd"
echo ""
echo "To view logs:"
echo "  oc logs -f deployment/ctfd -n ctfd"
echo ""
echo "IMPORTANT: Change the default passwords in 02-secrets.yaml for production use!"
echo ""
