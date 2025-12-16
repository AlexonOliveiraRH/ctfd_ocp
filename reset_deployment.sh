#!/bin/bash

# Script to completely reset the CTFd deployment

set -e

echo "========================================="
echo "Resetting CTFd Deployment"
echo "========================================="

echo ""
echo "WARNING: This will delete all data!"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Step 1: Deleting CTFd deployment..."
oc delete deployment ctfd -n ctfd --ignore-not-found=true
oc delete service ctfd -n ctfd --ignore-not-found=true

echo ""
echo "Step 2: Deleting database and cache..."
oc delete deployment mariadb -n ctfd --ignore-not-found=true
oc delete service mariadb -n ctfd --ignore-not-found=true
oc delete deployment redis -n ctfd --ignore-not-found=true
oc delete service redis -n ctfd --ignore-not-found=true

echo ""
echo "Step 3: Deleting all PVCs (this will delete all data)..."
oc delete pvc --all -n ctfd

echo ""
echo "Step 4: Waiting for cleanup..."
sleep 10

echo ""
echo "Step 5: Recreating secrets..."
oc delete secret ctfd-secrets redis-secrets -n ctfd --ignore-not-found=true
oc apply -f 02-secrets.yaml

echo ""
echo "Step 6: Deploying MariaDB..."
oc apply -f 03-mariadb.yaml
echo "Waiting for MariaDB to be ready..."
oc wait --for=condition=available --timeout=300s deployment/mariadb -n ctfd

echo ""
echo "Step 7: Waiting extra time for MariaDB initialization..."
sleep 30

echo ""
echo "Step 8: Deploying Redis..."
oc apply -f 04-redis.yaml
echo "Waiting for Redis to be ready..."
oc wait --for=condition=available --timeout=180s deployment/redis -n ctfd

echo ""
echo "Step 9: Deploying CTFd application..."
oc apply -f 05-ctfd.yaml

echo ""
echo "Step 10: Waiting for CTFd to be ready..."
oc wait --for=condition=available --timeout=300s deployment/ctfd -n ctfd

echo ""
echo "========================================="
echo "Reset Complete!"
echo "========================================="
echo ""
echo "Checking CTFd logs..."
oc logs deployment/ctfd -n ctfd --tail=20

echo ""
echo "Get the CTFd URL with:"
echo "  oc get route ctfd -n ctfd -o jsonpath='{.spec.host}'"
echo ""
