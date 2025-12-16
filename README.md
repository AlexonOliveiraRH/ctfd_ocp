# CTFd OpenShift Deployment Guide

This guide will help you deploy CTFd on Single-Node OpenShift 4.20.6.

## Prerequisites

- OpenShift 4.20.6 cluster (single-node) running
- `oc` CLI tool installed and configured
- Cluster admin access or sufficient permissions to create namespaces, deployments, PVCs, and routes

## Architecture

The deployment consists of:
- **CTFd**: Main application (1 replica)
- **MariaDB**: Database backend (1 replica, 10Gi storage)
- **Redis**: Caching layer (1 replica, 1Gi storage)
- **OpenShift Route**: HTTPS ingress with edge TLS termination

## Files Overview

1. **01-namespace.yaml** - Creates the `ctfd` namespace
2. **02-secrets.yaml** - Contains database and application secrets
3. **03-mariadb.yaml** - MariaDB deployment, service, and PVC
4. **04-redis.yaml** - Redis deployment, service, and PVC
5. **05-ctfd.yaml** - CTFd application deployment, service, and PVCs
6. **06-route.yaml** - OpenShift route for external access
7. **deploy.sh** - Automated deployment script
8. **reset_deployment.sh** - Script to completely reset the deployment
9. **README.md** - Complete deployment guide

## Quick Start

### Option 1: Automated Deployment (Recommended)

```bash
# Make the script executable
chmod +x deploy.sh

# Run the deployment script
./deploy.sh
```

### Option 2: Manual Deployment

```bash
# 1. Create namespace
oc apply -f 01-namespace.yaml

# 2. IMPORTANT: Edit 02-secrets.yaml first!
# - Change all passwords
# - Ensure SECRET_KEY is a string (e.g., "changeme123456" not "123456")
# - Ensure DATABASE_URL password matches MYSQL_PASSWORD
# - Ensure DATABASE_URL includes ?charset=utf8mb4
# Then apply:
oc apply -f 02-secrets.yaml

# 3. Deploy MariaDB
oc apply -f 03-mariadb.yaml
oc wait --for=condition=available --timeout=300s deployment/mariadb -n ctfd

# 4. Wait for MariaDB to fully initialize (important!)
sleep 30

# 5. Verify and fix database user if needed
MARIADB_POD=$(oc get pods -n ctfd -l app=mariadb -o jsonpath='{.items[0].metadata.name}')
oc exec -i $MARIADB_POD -n ctfd -- mysql -uroot -pYOUR_ROOT_PASSWORD <<EOF
SELECT user, host FROM mysql.user WHERE user='ctfd';
SHOW DATABASES;
EOF

# 6. Deploy Redis
oc apply -f 04-redis.yaml
oc wait --for=condition=available --timeout=180s deployment/redis -n ctfd

# 7. Deploy CTFd
oc apply -f 05-ctfd.yaml
oc wait --for=condition=available --timeout=300s deployment/ctfd -n ctfd

# 8. Create route
oc apply -f 06-route.yaml

# 9. Get the URL
oc get route ctfd -n ctfd -o jsonpath='{.spec.host}'
```

## Security Configuration

**IMPORTANT**: Before deploying to production, you must change the default passwords in `02-secrets.yaml`:

```yaml
stringData:
  DATABASE_URL: "mysql+pymysql://ctfd:YOUR_PASSWORD@mariadb:3306/ctfd?charset=utf8mb4"
  SECRET_KEY: "YOUR_SECRET_KEY_HERE"  # Must be a STRING, not a number
  MYSQL_ROOT_PASSWORD: "YOUR_ROOT_PASSWORD"
  MYSQL_PASSWORD: "YOUR_PASSWORD"  # Must match password in DATABASE_URL
  MYSQL_DATABASE: "ctfd"
```

**Critical Notes:**
- The `SECRET_KEY` must be a **string** (e.g., "mysecret123"), not just numbers like "123456"
- The password in `DATABASE_URL` must match `MYSQL_PASSWORD`
- The `DATABASE_URL` must include `?charset=utf8mb4` to prevent database creation errors

Generate a secure SECRET_KEY:
```bash
python3 -c 'import secrets; print(secrets.token_hex(32))'
```

## Verification

Check deployment status:
```bash
# View all pods
oc get pods -n ctfd

# Check pod logs
oc logs -f deployment/ctfd -n ctfd
oc logs -f deployment/mariadb -n ctfd
oc logs -f deployment/redis -n ctfd

# Get route URL
oc get route ctfd -n ctfd
```

## Accessing CTFd

Once deployed, access CTFd at:
```
https://<route-host>
```

The route host can be found with:
```bash
oc get route ctfd -n ctfd -o jsonpath='{.spec.host}'
```

## Storage

The deployment uses PersistentVolumeClaims:
- MariaDB: 10Gi for database storage
- Redis: 1Gi for cache storage
- CTFd Uploads: 5Gi for file uploads
- CTFd Logs: 2Gi for application logs

## Resource Limits

Default resource allocations:
- **MariaDB**: 256Mi-512Mi RAM, 250m-500m CPU
- **Redis**: 128Mi-256Mi RAM, 100m-200m CPU
- **CTFd**: 512Mi-1Gi RAM, 250m-1000m CPU

Adjust these in the deployment files based on your needs.

## Scaling

To scale CTFd horizontally:
```bash
oc scale deployment/ctfd --replicas=3 -n ctfd
```

Note: MariaDB and Redis are configured for single-replica deployment. For production high-availability, consider using StatefulSets or managed database services.

## Troubleshooting

### Pods not starting
```bash
# Check pod events
oc describe pod <pod-name> -n ctfd

# Check logs
oc logs <pod-name> -n ctfd
```

### Database connection issues
```bash
# Test database connectivity
oc exec -it deployment/ctfd -n ctfd -- nc -zv mariadb 3306
```

### Common Issues and Solutions

#### Error: "Access denied for user 'ctfd'"
This means the password in `DATABASE_URL` doesn't match `MYSQL_PASSWORD`. Ensure both use the same password.

Fix manually:
```bash
# Get the MariaDB pod
MARIADB_POD=$(oc get pods -n ctfd -l app=mariadb -o jsonpath='{.items[0].metadata.name}')

# Fix user permissions (replace YOUR_PASSWORD with your actual password)
oc exec -i $MARIADB_POD -n ctfd -- mysql -uroot -pYOUR_ROOT_PASSWORD <<EOF
DROP USER IF EXISTS 'ctfd'@'%';
CREATE USER 'ctfd'@'%' IDENTIFIED BY 'YOUR_PASSWORD';
GRANT ALL PRIVILEGES ON ctfd.* TO 'ctfd'@'%';
FLUSH PRIVILEGES;
EOF

# Update the secret and restart
oc apply -f 02-secrets.yaml
oc rollout restart deployment/ctfd -n ctfd
```

#### Error: "Can't create database 'ctfd'; database exists"
This happens when the `DATABASE_URL` doesn't include the charset parameter.

Fix: Ensure your `DATABASE_URL` includes `?charset=utf8mb4`:
```
DATABASE_URL: "mysql+pymysql://ctfd:password@mariadb:3306/ctfd?charset=utf8mb4"
```

If the database is corrupted, you can use the reset script:
```bash
chmod +x reset_deployment.sh
./reset_deployment.sh
```

Or manually recreate the database:
```bash
MARIADB_POD=$(oc get pods -n ctfd -l app=mariadb -o jsonpath='{.items[0].metadata.name}')
oc exec -i $MARIADB_POD -n ctfd -- mysql -uroot -pYOUR_ROOT_PASSWORD <<EOF
DROP DATABASE IF EXISTS ctfd;
CREATE DATABASE ctfd CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON ctfd.* TO 'ctfd'@'%';
FLUSH PRIVILEGES;
EOF

oc rollout restart deployment/ctfd -n ctfd
```

#### Error: "TypeError: 'int' object is not iterable" (SECRET_KEY error)
The `SECRET_KEY` must be a string, not just numbers.

Wrong: `SECRET_KEY: "123456"` (interpreted as integer)
Correct: `SECRET_KEY: "changeme123456"` or any alphanumeric string

Fix:
```bash
# Generate a proper secret key
python3 -c 'import secrets; print(secrets.token_hex(32))'

# Update 02-secrets.yaml with the generated key
# Then apply:
oc apply -f 02-secrets.yaml
oc rollout restart deployment/ctfd -n ctfd
```

### Storage issues
```bash
# Check PVC status
oc get pvc -n ctfd

# Describe PVC
oc describe pvc <pvc-name> -n ctfd
```

## Backup

To backup the database:
```bash
# Create a backup
oc exec -it deployment/mariadb -n ctfd -- mysqldump -u ctfd -p ctfd > ctfd_backup.sql
```

To backup uploads:
```bash
# Copy uploads directory
oc rsync deployment/ctfd:/var/uploads ./uploads-backup -n ctfd
```

## Cleanup

### Complete Reset

If you need to completely reset the deployment and start fresh:

```bash
# Use the reset script (WARNING: Deletes ALL data)
chmod +x reset_deployment.sh
./reset_deployment.sh
```

This script will:
- Delete all CTFd, MariaDB, and Redis deployments
- Delete all PVCs (destroying all data)
- Recreate everything from scratch with proper initialization timing

### Partial Cleanup

To remove the entire deployment:
```bash
# Delete namespace (removes all resources)
oc delete namespace ctfd
```

Or delete individual components:
```bash
oc delete -f 06-route.yaml
oc delete -f 05-ctfd.yaml
oc delete -f 04-redis.yaml
oc delete -f 03-mariadb.yaml
oc delete -f 02-secrets.yaml
oc delete -f 01-namespace.yaml
```

## Additional Configuration

### Custom Domain

To use a custom domain, edit `06-route.yaml`:
```yaml
spec:
  host: ctf.yourdomain.com
```

### Environment Variables

Additional CTFd environment variables can be added to `05-ctfd.yaml` in the `env` section. See [CTFd documentation](https://docs.ctfd.io/) for available options.

## Support

- CTFd Documentation: https://docs.ctfd.io/
- OpenShift Documentation: https://docs.openshift.com/
- CTFd GitHub: https://github.com/CTFd/CTFd
