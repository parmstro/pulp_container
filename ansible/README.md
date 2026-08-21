# Ansible Automation for pulp_container Tag List Bypass Optimization

This directory contains Ansible playbooks for safely deploying and managing the pulp_container tag list bypass optimization on Red Hat Satellite 6.19.3 servers.

## Overview

The tag list bypass optimization dramatically improves sync performance (50-100x faster) for container repositories with specific tag lists. These playbooks handle:

- ✅ Automatic backups before deployment
- ✅ Safe service management
- ✅ Database migration
- ✅ Verification and health checks
- ✅ Automatic rollback on failure
- ✅ Manual rollback capability

## Prerequisites

### On the Control Node (where you run ansible)

```bash
# Install Ansible
pip3 install ansible

# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml

# Or install manually:
# ansible-galaxy collection install community.postgresql community.general
```

### On the Satellite Server

- Red Hat Satellite 6.19.3 installed
- PostgreSQL accessible
- Root SSH access or sudo privileges
- pulp_container already installed

### SSH Authentication

You have two options for SSH authentication:

**Option 1: Password Authentication** (simpler, requires password each run)
```bash
# Requires sshpass to be installed
sudo dnf install sshpass  # RHEL/CentOS
# or
sudo apt install sshpass   # Debian/Ubuntu

# Method 1a: Interactive password prompt (recommended)
ansible-playbook -i inventory.yml <playbook.yml> --ask-pass

# Method 1b: Use a password file (for automation)
# Create password file (already gitignored)
echo "your_password" > .claude.password.txt
chmod 600 .claude.password.txt

# Run with password file
ansible-playbook -i inventory.yml <playbook.yml> --extra-vars "ansible_password=$(cat .claude.password.txt)"
```

**⚠️ Security Note:** Password files are automatically excluded from git via `.gitignore`. Never commit passwords to version control!

**Option 2: SSH Key Authentication** (recommended for automation)
```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "ansible-automation"

# Copy to Satellite
ssh-copy-id ansiblerunner@satellite1.parmstrong.ca

# Run playbooks without --ask-pass
ansible-playbook -i inventory.yml <playbook.yml>
```

### Source Code

Ensure the optimized pulp_container code is available at the path specified in `inventory.yml`:

```yaml
pulp_container_repo_path: /home/ansiblerunner/foreman/pulp_container
pulp_container_branch: feature/bypass-taglist-sync-optimization
```

## Quick Start

### 1. Configure Inventory

Edit `inventory.yml` with your Satellite server details:

```yaml
satellite1:
  ansible_host: satellite1.parmstrong.ca
  ansible_user: root
```

### 2. Test Connection

```bash
ansible -i inventory.yml satellite_servers -m ping
```

### 3. Verify Current State

```bash
ansible-playbook -i inventory.yml verify-deployment.yml
```

This shows whether the optimization is already deployed.

### 4. Deploy the Optimization

```bash
# Dry-run first (recommended)
ansible-playbook -i inventory.yml deploy-optimization.yml --check

# Actual deployment
ansible-playbook -i inventory.yml deploy-optimization.yml
```

The deployment will:
1. ✅ Backup all files and database state
2. ✅ Stop Pulp services
3. ✅ Deploy optimized files
4. ✅ Run database migration
5. ✅ Restart services
6. ✅ Verify deployment
7. ✅ Automatically rollback if anything fails

### 5. Verify Deployment

```bash
ansible-playbook -i inventory.yml verify-deployment.yml
```

## Playbooks Reference

### deploy-optimization.yml

**Purpose**: Deploy the tag list bypass optimization

**Usage**:
```bash
# Full deployment
ansible-playbook -i inventory.yml deploy-optimization.yml

# Dry-run
ansible-playbook -i inventory.yml deploy-optimization.yml --check

# Only create backups
ansible-playbook -i inventory.yml deploy-optimization.yml --tags backup

# Only verify (post-deployment)
ansible-playbook -i inventory.yml deploy-optimization.yml --tags verify
```

**What it does**:
- Pre-flight checks (Satellite version, services, database)
- Creates timestamped backup in `/var/lib/pulp-backups/`
- Stops Pulp services gracefully
- Deploys optimized Python files
- Runs database migration (adds `auto_discover_cosign` field)
- Restarts services
- Verifies deployment success
- Auto-rollback on any failure

**Output**:
- Backup location: `/var/lib/pulp-backups/YYYYMMDDTHHMMSS/`
- Deployment log: `/var/log/pulp-container-optimization-deploy-TIMESTAMP.log`

---

### rollback-optimization.yml

**Purpose**: Rollback the optimization to previous state

**Usage**:
```bash
# Rollback to latest backup
ansible-playbook -i inventory.yml rollback-optimization.yml

# Rollback to specific backup
ansible-playbook -i inventory.yml rollback-optimization.yml \
  -e backup_path=/var/lib/pulp-backups/20260814T120000

# Auto-confirm (skip prompt)
ansible-playbook -i inventory.yml rollback-optimization.yml \
  -e auto_confirm=true
```

**What it does**:
- Validates backup exists
- Shows confirmation prompt
- Stops Pulp services
- Restores files from backup
- Rolls back database migration
- Removes `auto_discover_cosign` field
- Restarts services
- Verifies rollback success

**Output**:
- Rollback log: `/var/log/pulp-container-optimization-rollback-TIMESTAMP.log`
- Success marker: `<backup_path>/ROLLBACK_SUCCESS.txt`

---

### verify-deployment.yml

**Purpose**: Check current deployment status

**Usage**:
```bash
ansible-playbook -i inventory.yml verify-deployment.yml
```

**What it shows**:
- Database column existence
- Migration status
- Service status
- API health
- Sample remote configurations

---

### list-backups.yml

**Purpose**: List all available backups

**Usage**:
```bash
ansible-playbook -i inventory.yml list-backups.yml
```

**What it shows**:
- All backup directories
- Creation timestamps
- Deployment/rollback status
- Backup manifests
- Latest backup symlink

---

### cleanup-backups.yml

**Purpose**: Remove old backups

**Usage**:
```bash
# Default: remove backups older than 30 days
ansible-playbook -i inventory.yml cleanup-backups.yml

# Custom retention
ansible-playbook -i inventory.yml cleanup-backups.yml \
  -e backup_retention_days=7
```

---

## Configuration Files

### inventory.yml

Main inventory file with Satellite server details.

**Key variables**:
- `ansible_host`: Satellite server hostname/IP
- `ansible_user`: SSH user (usually root)
- `backup_base_dir`: Where backups are stored (default: `/var/lib/pulp-backups`)
- `backup_retention_days`: How long to keep backups (default: 30)
- `pulp_services`: List of Pulp systemd services

### group_vars/satellite_servers.yml

Group variables for all Satellite servers.

**Key variables**:
- `pulp_container_python_path`: Python package location
- `pulp_container_files_to_backup`: Files to backup
- `migration_file`: Migration filename

## Directory Structure

```
ansible/
├── README.md                        # This file
├── inventory.yml                    # Inventory configuration
├── group_vars/
│   └── satellite_servers.yml       # Group variables
├── deploy-optimization.yml          # Main deployment playbook
├── rollback-optimization.yml        # Rollback playbook
├── rollback-tasks.yml              # Shared rollback tasks
├── verify-deployment.yml           # Verification playbook
├── list-backups.yml                # List backups playbook
└── cleanup-backups.yml             # Cleanup old backups
```

## Backup Structure

Each deployment creates a timestamped backup:

```
/var/lib/pulp-backups/
├── 20260814T120000/                # Timestamp-based directory
│   ├── BACKUP_MANIFEST.txt         # Backup metadata
│   ├── DEPLOYMENT_SUCCESS.txt      # Deployment success marker (if deployed)
│   ├── ROLLBACK_SUCCESS.txt        # Rollback marker (if rolled back)
│   ├── models.py                   # Backed up Python files
│   ├── sync_stages.py
│   ├── synchronize.py
│   ├── migrations/                 # Full migrations directory
│   ├── migration_state.json        # Migration state snapshot
│   └── container_containerremote.sql  # Database table backup
└── latest -> 20260814T120000/      # Symlink to most recent backup
```

## Common Workflows

### Initial Deployment

```bash
# 1. Check current state
ansible-playbook -i inventory.yml verify-deployment.yml

# 2. Dry-run deployment
ansible-playbook -i inventory.yml deploy-optimization.yml --check

# 3. Deploy
ansible-playbook -i inventory.yml deploy-optimization.yml

# 4. Verify
ansible-playbook -i inventory.yml verify-deployment.yml
```

### Testing and Rollback

```bash
# 1. Deploy
ansible-playbook -i inventory.yml deploy-optimization.yml

# 2. Test (perform manual testing on Satellite)

# 3. If issues found, rollback
ansible-playbook -i inventory.yml rollback-optimization.yml

# 4. Verify rollback
ansible-playbook -i inventory.yml verify-deployment.yml
```

### Backup Management

```bash
# List all backups
ansible-playbook -i inventory.yml list-backups.yml

# Clean up old backups
ansible-playbook -i inventory.yml cleanup-backups.yml
```

## Safety Features

### Automatic Rollback

If deployment fails at any step, the playbook automatically:
1. Stops the deployment
2. Restores files from backup
3. Rolls back the database migration
4. Restarts services
5. Preserves the backup for investigation

### Pre-flight Checks

Before deploying, the playbook verifies:
- ✅ Running as root
- ✅ Satellite version detected
- ✅ pulp_container is installed
- ✅ PostgreSQL is accessible
- ✅ Database is responsive
- ✅ Services are available

### Backup Verification

Before rollback, the playbook:
- ✅ Confirms backup exists
- ✅ Shows backup manifest
- ✅ Prompts for confirmation
- ✅ Validates restored files

## Troubleshooting

### Deployment Fails

1. **Check the deployment log**:
   ```bash
   ls -lt /var/log/pulp-container-optimization-deploy-*.log | head -1
   cat <log file>
   ```

2. **Verify services**:
   ```bash
   satellite-maintain health check
   systemctl status pulpcore-worker@1
   ```

3. **Check backup location**:
   ```bash
   ansible-playbook -i inventory.yml list-backups.yml
   ```

4. **Manual rollback if needed**:
   ```bash
   ansible-playbook -i inventory.yml rollback-optimization.yml \
     -e backup_path=/var/lib/pulp-backups/<timestamp>
   ```

### Services Won't Start

```bash
# Check service logs
journalctl -u pulpcore-api -n 50
journalctl -u pulpcore-worker@1 -n 50

# Check for Python errors
python3 -m py_compile /usr/lib/python3.11/site-packages/pulp_container/app/models.py

# Verify database
sudo -u postgres psql -d pulpcore -c "\d container_containerremote"
```

### Migration Fails

```bash
# Check migration status
sudo -u pulp pulpcore-manager showmigrations container

# Check for pending migrations
sudo -u pulp pulpcore-manager migrate --plan

# Manual migration rollback if needed
sudo -u pulp pulpcore-manager migrate container 0050_alter_containernamespace_options
```

### Rollback Fails

If automated rollback fails:

```bash
# Stop services
systemctl stop pulpcore-api pulpcore-content pulpcore-worker@*

# Manually restore files
BACKUP_PATH=/var/lib/pulp-backups/latest
cp $BACKUP_PATH/models.py /usr/lib/python3.11/site-packages/pulp_container/app/
cp $BACKUP_PATH/sync_stages.py /usr/lib/python3.11/site-packages/pulp_container/app/tasks/
cp $BACKUP_PATH/synchronize.py /usr/lib/python3.11/site-packages/pulp_container/app/tasks/

# Restore migrations
rm -rf /usr/lib/python3.11/site-packages/pulp_container/app/migrations
cp -r $BACKUP_PATH/migrations /usr/lib/python3.11/site-packages/pulp_container/app/

# Rollback migration
sudo -u pulp pulpcore-manager migrate container 0050_alter_containernamespace_options

# Restore database table
sudo -u postgres psql -d pulpcore -f $BACKUP_PATH/container_containerremote.sql

# Start services
systemctl start pulpcore-api pulpcore-content pulpcore-worker@*
```

## Testing the Optimization

After successful deployment, test the optimization:

```bash
# SSH to Satellite
ssh root@satellite1.parmstrong.ca

# Create test repository with specific tags (triggers bypass)
hammer repository create \
  --name "test-bypass" \
  --product "Test" \
  --content-type "docker" \
  --url "https://quay.io" \
  --docker-upstream-name "openshift-release-dev/ocp-v4.0-art-dev" \
  --organization "Default Organization"

# Get remote ID and configure includes
REMOTE_ID=$(hammer --output json repository info --name "test-bypass" | jq -r '.["Remote ID"]')

curl -X PATCH -u admin:password -k \
  -H "Content-Type: application/json" \
  https://satellite1.parmstrong.ca/pulp/api/v3/remotes/container/container/$REMOTE_ID/ \
  -d '{"includes": ["4.12.0-x86_64", "4.12.1-x86_64"]}'

# Sync and watch logs
hammer repository synchronize --name "test-bypass" --async

# In another terminal, watch for bypass activation
journalctl -u pulpcore-worker* -f | grep -i "bypass\|cosign"
```

**Expected log output**:
```
INFO: Bypassing /tags/list enumeration - syncing 2 explicit references directly
INFO: Auto-discovering cosign companion tags via HEAD probing
INFO: Found N cosign companion tag(s) for synced manifests
```

## Advanced Usage

### Multiple Satellite Servers

Add multiple hosts to `inventory.yml`:

```yaml
satellite_servers:
  hosts:
    satellite1:
      ansible_host: satellite1.parmstrong.ca
    satellite2:
      ansible_host: satellite2.parmstrong.ca
    satellite3:
      ansible_host: satellite3.parmstrong.ca
```

Deploy to all:
```bash
ansible-playbook -i inventory.yml deploy-optimization.yml
```

Deploy to specific host:
```bash
ansible-playbook -i inventory.yml deploy-optimization.yml --limit satellite1
```

### Custom Backup Location

```bash
ansible-playbook -i inventory.yml deploy-optimization.yml \
  -e backup_base_dir=/custom/backup/path
```

### Skip Confirmation Prompts

```bash
ansible-playbook -i inventory.yml rollback-optimization.yml \
  -e auto_confirm=true
```

### Verbose Output

```bash
ansible-playbook -i inventory.yml deploy-optimization.yml -vvv
```

## Support

For issues or questions:

1. Check this README
2. Review deployment/rollback logs
3. Run verification playbook
4. Check Satellite health: `satellite-maintain health check`

## License

Same as pulp_container project

## Contributors

- Paul Armstrong (parmstro)
- Claude (Anthropic) - Initial automation development
