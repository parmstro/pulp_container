# Quick Start Guide - Ansible Deployment

Deploy the pulp_container tag list bypass optimization to Satellite 6.19.3 in 5 minutes.

## Step 0: Install Prerequisites (30 seconds)

```bash
cd /home/ansiblerunner/foreman/pulp_container/ansible

# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml
```

## Step 1: Edit Inventory (1 minute)

```bash
cd /home/ansiblerunner/foreman/pulp_container/ansible
vi inventory.yml
```

Update these values:
```yaml
ansible_host: satellite1.parmstrong.ca  # Your Satellite hostname
ansible_user: root                       # SSH user
```

Save and exit (`:wq`)

## Step 2: Test Prerequisites (1 minute)

```bash
# With password authentication
ansible-playbook -i inventory.yml test-prerequisites.yml --ask-pass

# Or with SSH keys (if configured)
# ansible-playbook -i inventory.yml test-prerequisites.yml
```

Look for the final message:
- ✓ **"ALL PREREQUISITES MET"** → Continue to Step 3
- ✗ **"PREREQUISITES NOT MET"** → Fix the issues shown, then retry

## Step 3: Deploy (2 minutes)

```bash
# Dry-run first (recommended)
ansible-playbook -i inventory.yml deploy-optimization.yml --check --ask-pass

# Actual deployment
ansible-playbook -i inventory.yml deploy-optimization.yml --ask-pass
```

The playbook will:
1. Backup everything
2. Deploy the optimization
3. Run migrations
4. Restart services
5. Verify success

**Auto-rollback**: If anything fails, it automatically rolls back.

## Step 4: Verify (30 seconds)

```bash
ansible-playbook -i inventory.yml verify-deployment.yml --ask-pass
```

Look for: **"Optimization is DEPLOYED"**

## Step 5: Test the Optimization (Optional)

SSH to your Satellite and run a quick sync test:

```bash
ssh root@satellite1.parmstrong.ca

# Watch for bypass activation in logs (in background)
journalctl -u pulpcore-worker* -f | grep -i bypass &

# Create test repo with specific tags
hammer repository create \
  --name "ocp-test" \
  --product "Test" \
  --content-type "docker" \
  --url "https://quay.io" \
  --docker-upstream-name "openshift-release-dev/ocp-v4.0-art-dev"

# Configure specific tags (no wildcards)
REMOTE_ID=$(hammer --output json repository info --name "ocp-test" | jq -r '.["Remote ID"]')

curl -X PATCH -u admin:password -k \
  -H "Content-Type: application/json" \
  https://satellite1.parmstrong.ca/pulp/api/v3/remotes/container/container/$REMOTE_ID/ \
  -d '{"includes": ["4.12.0-x86_64"]}'

# Sync and time it
time hammer repository synchronize --name "ocp-test"
```

**Expected results**:
- Sync completes in ~3-5 seconds (vs minutes)
- Logs show: `"Bypassing /tags/list enumeration - syncing 1 explicit references directly"`

---

## Rollback (If Needed)

If you need to undo the deployment:

```bash
# Rollback to latest backup
ansible-playbook -i inventory.yml rollback-optimization.yml

# Verify rollback
ansible-playbook -i inventory.yml verify-deployment.yml
```

Look for: **"Optimization is NOT DEPLOYED"**

---

## Troubleshooting

### Connection Issues
```bash
# Test SSH connection
ansible -i inventory.yml satellite_servers -m ping

# If fails, check:
# - Can you SSH manually? ssh root@satellite1.parmstrong.ca
# - Is the hostname correct in inventory.yml?
# - Are SSH keys set up? ssh-copy-id root@satellite1.parmstrong.ca
```

### Prerequisites Not Met
```bash
# Re-run the prerequisites check to see specific issues
ansible-playbook -i inventory.yml test-prerequisites.yml

# Common fixes:
# - PostgreSQL not running: systemctl start postgresql
# - Missing Ansible collection: ansible-galaxy collection install community.postgresql
# - Wrong source path: update pulp_container_repo_path in inventory.yml
```

### Deployment Failed
```bash
# The playbook auto-rolls back on failure
# Check the deployment log for details:
ls -lt /var/log/pulp-container-optimization-deploy-*.log | head -1

# View the log:
cat <log-file>

# List available backups:
ansible-playbook -i inventory.yml list-backups.yml

# Manual rollback to specific backup if needed:
ansible-playbook -i inventory.yml rollback-optimization.yml \
  -e backup_path=/var/lib/pulp-backups/<timestamp>
```

---

## What Happens Behind the Scenes

### Deployment creates:
- **Backup**: `/var/lib/pulp-backups/YYYYMMDDTHHMMSS/`
  - All modified Python files
  - Complete migrations directory
  - Database table backup
  - Migration state snapshot

### Files modified:
- `models.py` - Adds `auto_discover_cosign` field
- `sync_stages.py` - Adds bypass logic
- `synchronize.py` - Passes mirror parameter
- Migration: `0051_containerremote_auto_discover_cosign.py`

### Database changes:
- Adds column: `container_containerremote.auto_discover_cosign BOOLEAN DEFAULT TRUE`

### Services managed:
- `pulpcore-api`
- `pulpcore-content`
- `pulpcore-worker@1` through `pulpcore-worker@4`

---

## Next Steps After Deployment

1. **Monitor syncs** - Watch for the bypass activation in logs
2. **Measure performance** - Compare sync times before/after
3. **Read the full documentation** - See `README.md` for advanced usage
4. **Test thoroughly** - Try different sync scenarios
5. **Plan for production** - Document your testing results

---

## Getting Help

1. **Check README.md** - Comprehensive documentation
2. **Run verify playbook** - `ansible-playbook -i inventory.yml verify-deployment.yml`
3. **Check logs** - `/var/log/pulp-container-optimization-*.log`
4. **Satellite health** - `satellite-maintain health check`

---

## Summary of Commands

```bash
# Setup
cd /home/ansiblerunner/foreman/pulp_container/ansible
vi inventory.yml  # Edit your Satellite hostname

# Deploy
ansible-playbook -i inventory.yml test-prerequisites.yml
ansible-playbook -i inventory.yml deploy-optimization.yml
ansible-playbook -i inventory.yml verify-deployment.yml

# Rollback (if needed)
ansible-playbook -i inventory.yml rollback-optimization.yml

# Utilities
ansible-playbook -i inventory.yml list-backups.yml
ansible-playbook -i inventory.yml cleanup-backups.yml
```

That's it! The optimization is deployed and ready to use.
