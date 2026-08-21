# Testing Plan for Tag List Bypass Optimization

## Test Environment
- **Satellite Instance**: https://satellite1.parmstrong.ca
- **Target**: Red Hat Satellite 6.19.3
- **Test Repository**: OCP ART repo on Quay.io (50,000+ tags)

## Pre-Test Verification

### 1. Check Current Satellite Version
```bash
# SSH to satellite1.parmstrong.ca
satellite-maintain packages list | grep satellite
```

### 2. Verify Current pulp_container Version
```bash
# Check installed version
rpm -qa | grep pulp_container

# Check Python package
pip3 list | grep pulp-container
```

### 3. Baseline Performance Test (Before Optimization)
```bash
# Create a test remote with specific tags
hammer content-view create --name "test-ocp-baseline" --organization "Default Organization"

hammer repository create \
  --name "ocp-art-baseline" \
  --product "Red Hat OpenShift Container Platform" \
  --content-type "docker" \
  --url "https://quay.io/openshift-release-dev/ocp-v4.0-art-dev" \
  --docker-upstream-name "openshift-release-dev/ocp-v4.0-art-dev" \
  --organization "Default Organization"

# Sync with specific tags (includes filter)
# Note: Record start time
date && hammer repository synchronize \
  --name "ocp-art-baseline" \
  --organization "Default Organization" \
  --include-tags "4.12.0-x86_64,4.12.1-x86_64,4.12.2-x86_64"
```

**Expected baseline**: 3-8 minutes (depending on network)

---

## Installation Steps

### 1. Build RPM from Feature Branch
```bash
# On development machine
cd /home/ansiblerunner/foreman/pulp_container
git checkout feature/bypass-taglist-sync-optimization

# Build the RPM (adjust for your build process)
# This depends on how pulp_container is packaged for Satellite
```

### 2. Install on Satellite Instance
```bash
# Copy RPM to satellite instance
scp pulp_container-*.rpm root@satellite1.parmstrong.ca:/tmp/

# SSH to satellite
ssh root@satellite1.parmstrong.ca

# Stop pulp services
satellite-maintain service stop --only pulpcore-worker,pulpcore-api,pulpcore-content

# Install updated package
rpm -Uvh /tmp/pulp_container-*.rpm

# Run migrations
sudo -u postgres pulpcore-manager migrate

# Verify migration ran
sudo -u postgres pulpcore-manager showmigrations container | grep "0051_containerremote_auto_discover_cosign"
# Should show: [X] 0051_containerremote_auto_discover_cosign

# Restart services
satellite-maintain service start
```

### 3. Verify Installation
```bash
# Check service status
satellite-maintain health check

# Verify field exists in database
sudo -u postgres psql -d pulpcore -c "SELECT column_name, data_type, column_default FROM information_schema.columns WHERE table_name='container_containerremote' AND column_name='auto_discover_cosign';"

# Expected output:
#     column_name      | data_type | column_default
# ---------------------+-----------+----------------
#  auto_discover_cosign | boolean   | true
```

---

## Test Cases

### Test 1: Verify Bypass Activates (Small Tag Set)

**Objective**: Confirm optimization activates for specific tag syncs

```bash
# Create new remote with specific tags (no wildcards)
hammer repository create \
  --name "ocp-art-optimized" \
  --product "Red Hat OpenShift Container Platform" \
  --content-type "docker" \
  --url "https://quay.io" \
  --docker-upstream-name "openshift-release-dev/ocp-v4.0-art-dev" \
  --organization "Default Organization"

# Configure includes via API (Satellite UI doesn't expose this yet)
# Get the remote ID first
REMOTE_ID=$(hammer --output json repository info --name "ocp-art-optimized" --organization "Default Organization" | jq -r '.["Remote ID"]')

# Update remote with includes
curl -X PATCH \
  -u admin:password \
  -H "Content-Type: application/json" \
  https://satellite1.parmstrong.ca/pulp/api/v3/remotes/container/container/$REMOTE_ID/ \
  -d '{
    "includes": ["4.12.0-x86_64", "4.12.1-x86_64", "4.12.2-x86_64"]
  }'

# Sync and time it
date && hammer repository synchronize \
  --name "ocp-art-optimized" \
  --organization "Default Organization" && date
```

**Expected Result**:
- ✅ Sync completes in 3-10 seconds (vs 3-8 minutes baseline)
- ✅ Logs show: "Bypassing /tags/list enumeration - syncing 3 explicit references directly"
- ✅ Logs show: "Auto-discovering cosign companion tags via HEAD probing"
- ✅ Synced manifests include cosign signatures (if they exist)

**Check logs**:
```bash
journalctl -u pulpcore-worker* --since "2 minutes ago" | grep -i "bypass\|cosign\|tags/list"
```

---

### Test 2: Verify Original Path for Wildcards

**Objective**: Confirm optimization doesn't activate with wildcards

```bash
# Update remote with wildcard
curl -X PATCH \
  -u admin:password \
  -H "Content-Type: application/json" \
  https://satellite1.parmstrong.ca/pulp/api/v3/remotes/container/container/$REMOTE_ID/ \
  -d '{
    "includes": ["4.12.*"]
  }'

# Sync
date && hammer repository synchronize \
  --name "ocp-art-optimized" \
  --organization "Default Organization" && date
```

**Expected Result**:
- ✅ Sync takes longer (uses original /tags/list path)
- ✅ Logs show: "Downloading tag list" (NOT "Bypassing")
- ✅ All 4.12.* tags are synced

---

### Test 3: Verify Mirror Mode Bypass Disabled

**Objective**: Confirm mirror mode uses original path

```bash
# Enable mirror mode on repository
hammer repository update \
  --name "ocp-art-optimized" \
  --mirror-on-sync true \
  --organization "Default Organization"

# Reset to specific tags (no wildcard)
curl -X PATCH \
  -u admin:password \
  -H "Content-Type: application/json" \
  https://satellite1.parmstrong.ca/pulp/api/v3/remotes/container/container/$REMOTE_ID/ \
  -d '{
    "includes": ["4.12.0-x86_64"]
  }'

# Sync
hammer repository synchronize \
  --name "ocp-art-optimized" \
  --organization "Default Organization"
```

**Expected Result**:
- ✅ Bypass does NOT activate (mirror mode requires full tag list)
- ✅ Logs show: "Downloading tag list"
- ✅ Mirror behavior works correctly (removes tags not in upstream)

---

### Test 4: Verify Cosign Tag Discovery

**Objective**: Confirm cosign companion tags are discovered and synced

```bash
# Sync a repository known to have cosign signatures
# Example: Red Hat's signed images
hammer repository create \
  --name "rhel8-ubi-cosign-test" \
  --product "Red Hat Enterprise Linux" \
  --content-type "docker" \
  --url "https://registry.access.redhat.com" \
  --docker-upstream-name "ubi8" \
  --organization "Default Organization"

# Get remote ID
REMOTE_ID=$(hammer --output json repository info --name "rhel8-ubi-cosign-test" --organization "Default Organization" | jq -r '.["Remote ID"]')

# Set specific tag
curl -X PATCH \
  -u admin:password \
  -H "Content-Type: application/json" \
  https://satellite1.parmstrong.ca/pulp/api/v3/remotes/container/container/$REMOTE_ID/ \
  -d '{
    "includes": ["latest"]
  }'

# Sync
hammer repository synchronize \
  --name "rhel8-ubi-cosign-test" \
  --organization "Default Organization"

# Check for cosign tags in the synced content
hammer docker tag list --repository "rhel8-ubi-cosign-test" | grep sha256-
```

**Expected Result**:
- ✅ Main tag synced
- ✅ Cosign companion tags discovered (sha256-*.sig, sha256-*.att, etc.)
- ✅ Logs show: "Found N cosign companion tag(s) for synced manifests"

---

### Test 5: Performance Comparison

**Objective**: Quantify performance improvement

```bash
# Test with 1 tag
echo "=== Testing 1 tag ===" 
time hammer repository synchronize --name "ocp-art-optimized" # includes=["4.12.0-x86_64"]

# Test with 5 tags
curl -X PATCH ... -d '{"includes": ["4.12.0-x86_64", "4.12.1-x86_64", "4.12.2-x86_64", "4.12.3-x86_64", "4.12.4-x86_64"]}'
echo "=== Testing 5 tags ===" 
time hammer repository synchronize --name "ocp-art-optimized"

# Test with 10 tags
# ... add 10 tags to includes
echo "=== Testing 10 tags ===" 
time hammer repository synchronize --name "ocp-art-optimized"

# Compare to baseline (full tag list fetch)
curl -X PATCH ... -d '{"includes": null}'  # Clear includes
echo "=== Testing full sync (baseline) ===" 
time hammer repository synchronize --name "ocp-art-optimized"
```

**Expected Results**:
| Tag Count | Optimized | Baseline | Speedup |
|-----------|-----------|----------|---------|
| 1 tag     | ~3s       | 3-8 min  | 60-160x |
| 5 tags    | ~5s       | 3-8 min  | 36-96x  |
| 10 tags   | ~8s       | 3-8 min  | 22-60x  |
| All tags  | N/A       | 3-8 min  | N/A     |

---

## Verification Queries

### Check Migration Status
```sql
sudo -u postgres psql -d pulpcore -c "
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name='container_containerremote' 
  AND column_name='auto_discover_cosign';
"
```

### Check All Remotes Have Default Value
```sql
sudo -u postgres psql -d pulpcore -c "
SELECT name, auto_discover_cosign 
FROM container_containerremote 
LIMIT 10;
"
```

Expected: All should show `t` (true)

### Check Bypass Conditions
```sql
sudo -u postgres psql -d pulpcore -c "
SELECT 
  name,
  includes,
  excludes,
  auto_discover_cosign,
  CASE 
    WHEN includes IS NOT NULL AND excludes IS NULL THEN 'Potential bypass'
    ELSE 'Normal path'
  END as bypass_eligible
FROM container_containerremote;
"
```

---

## Rollback Plan

If issues arise:

### Quick Rollback (Disable Feature)
```sql
-- Disable auto_discover_cosign for all remotes
sudo -u postgres psql -d pulpcore -c "
UPDATE container_containerremote 
SET auto_discover_cosign = false;
"

-- Restart services
satellite-maintain service restart --only pulpcore-worker,pulpcore-api
```

### Full Rollback (Restore Previous Version)
```bash
# Stop services
satellite-maintain service stop --only pulpcore-worker,pulpcore-api,pulpcore-content

# Downgrade package
yum downgrade pulp_container

# Rollback migration
sudo -u postgres pulpcore-manager migrate container 0050_alter_containernamespace_options

# Restart services
satellite-maintain service start
```

---

## Success Criteria

✅ **All tests pass**:
1. Bypass activates for specific tag lists
2. Original path used for wildcards
3. Original path used for mirror mode
4. Cosign tags discovered and synced
5. Performance improvement: 50-100x speedup for small tag sets

✅ **No regressions**:
1. Existing syncs still work
2. Mirror mode still works
3. Wildcard syncs still work
4. Signature syncs still work

✅ **Production ready**:
1. No errors in logs
2. No failed syncs
3. Performance meets expectations
4. Satellite health check passes

---

## Monitoring Post-Deployment

### Key Metrics to Watch
1. **Sync duration** for specific-tag repositories
2. **Failed sync rate** (should not increase)
3. **Cosign tag sync rate** (signatures should still sync)
4. **Error logs** for bypass-related issues

### Log Patterns to Monitor
```bash
# Success patterns
journalctl -u pulpcore-worker* | grep "Bypassing /tags/list"
journalctl -u pulpcore-worker* | grep "Auto-discovering cosign"

# Error patterns (shouldn't occur)
journalctl -u pulpcore-worker* | grep -i "error.*bypass\|error.*cosign"
```

---

## Next Steps After Testing

1. Document performance improvements
2. Create knowledge base article for Satellite admins
3. Submit upstream PR to pulp_container project
4. Consider backporting to earlier Satellite versions
5. Add UI toggle for auto_discover_cosign in future release
