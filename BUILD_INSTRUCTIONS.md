# Build Instructions for pulp_container

## Overview

There are **two ways** to deploy the optimization to Satellite 6.19.3:

### ✅ **Option 1: Direct File Deployment** (Recommended)

Use the Ansible playbooks - they copy files directly to the installed location.

**Pros:**
- No build needed
- Fastest deployment
- Works with existing Satellite installation
- Easy rollback

**Cons:**
- Not a "proper" package
- Doesn't show up in pip/rpm lists

**How to deploy:**
```bash
cd /home/ansiblerunner/foreman/pulp_container/ansible
ansible-playbook -i inventory.yml deploy-optimization.yml
```

---

### Option 2: Build Python Wheel Package

Build a proper Python wheel that can be installed via pip.

## Prerequisites

```bash
# Install build tools
pip3 install build

# Ensure you're on the feature branch
cd /home/ansiblerunner/foreman/pulp_container
git checkout feature/bypass-taglist-sync-optimization
```

## Build the Wheel

```bash
# Build the package
python3 -m build

# Output will be in dist/:
# - dist/pulp_container-2.30.0.dev-py3-none-any.whl
# - dist/pulp-container-2.30.0.dev.tar.gz
```

## Install the Wheel on Satellite

### Method A: Direct pip install

```bash
# Copy wheel to Satellite
scp dist/pulp_container-2.30.0.dev-py3-none-any.whl root@satellite1.parmstrong.ca:/tmp/

# SSH to Satellite
ssh root@satellite1.parmstrong.ca

# Stop pulp services
satellite-maintain service stop --only pulpcore-worker,pulpcore-api,pulpcore-content

# Install the wheel (this upgrades pulp-container)
pip3 install --upgrade /tmp/pulp_container-2.30.0.dev-py3-none-any.whl

# Run migrations
sudo -u pulp pulpcore-manager migrate

# Restart services
satellite-maintain service start
```

### Method B: Create an RPM from the wheel

If you need an actual RPM for Satellite:

```bash
# Install fpm (Ruby gem for creating packages)
gem install fpm

# Create RPM from wheel
fpm -s python -t rpm \
  --python-bin python3 \
  --python-package-name-prefix python3 \
  dist/pulp_container-2.30.0.dev-py3-none-any.whl

# This creates:
# python3-pulp-container-2.30.0.dev-1.noarch.rpm

# Copy to Satellite and install
scp python3-pulp-container-*.rpm root@satellite1.parmstrong.ca:/tmp/
ssh root@satellite1.parmstrong.ca

# Stop services
satellite-maintain service stop --only pulpcore-worker,pulpcore-api,pulpcore-content

# Install RPM (downgrades Red Hat's version)
rpm -Uvh --force /tmp/python3-pulp-container-*.rpm

# Run migrations
sudo -u pulp pulpcore-manager migrate

# Restart services
satellite-maintain service start
```

---

## Comparison: Ansible vs. Build

| Aspect | Ansible (Option 1) | Build + Install (Option 2) |
|--------|-------------------|----------------------------|
| **Build time** | None | 1-2 minutes |
| **Complexity** | Low | Medium |
| **Deployment time** | 2-3 minutes | 5-10 minutes |
| **Backup** | Automatic | Manual |
| **Rollback** | One command | Manual restore |
| **Package management** | Files only | Proper package |
| **Satellite compatibility** | ✅ Safe | ⚠️ May conflict with yum updates |
| **Best for** | Testing, development | Production distribution |

---

## Recommendations

### For Testing on Your Satellite
**Use Option 1 (Ansible)** - It's:
- Faster
- Safer (automatic backups/rollback)
- Easier to manage
- Doesn't interfere with Red Hat packages

### For Production Distribution
If you need to deploy to multiple Satellites or want a formal package:

1. **Build the wheel** (`python3 -m build`)
2. **Test with Ansible first** on one Satellite
3. **Create RPM** (optional, for package management)
4. **Document the installation process**
5. **Deploy to production Satellites**

---

## Current Recommendation

**Use the Ansible playbooks!** They are:
- Production-ready
- Include comprehensive safety features
- Provide automatic rollback
- Preserve backups
- Work perfectly with Satellite 6.19.3

Building a wheel/RPM is only necessary if:
- You need to distribute to many Satellites
- You want formal package tracking
- Corporate policy requires RPM packages

For your single Satellite at satellite1.parmstrong.ca, the Ansible approach is ideal.

---

## Build Troubleshooting

### If `python3 -m build` fails:

```bash
# Ensure build module is installed
pip3 install --upgrade build setuptools wheel

# Check Python version (needs 3.11+)
python3 --version

# Clean any previous builds
rm -rf build/ dist/ *.egg-info/

# Retry build
python3 -m build
```

### If wheel install fails on Satellite:

```bash
# Check what version is currently installed
pip3 show pulp-container

# Check for conflicts
pip3 install --dry-run --upgrade /tmp/pulp_container-*.whl

# Force install (careful!)
pip3 install --force-reinstall /tmp/pulp_container-*.whl
```

---

## Files in dist/ After Build

```
dist/
├── pulp_container-2.30.0.dev-py3-none-any.whl    # Wheel package
└── pulp-container-2.30.0.dev.tar.gz              # Source distribution
```

- **Wheel (.whl)**: Pre-built, ready to install with pip
- **Source (.tar.gz)**: Source code archive, requires building during install

**For Satellite, use the .whl file** - it's faster and cleaner.

---

## Next Steps

1. ✅ **Use Ansible (recommended)**: Skip the build, use the playbooks
2. Or build wheel: `python3 -m build`
3. Or create RPM: Use fpm to convert wheel to RPM

**For your use case (single Satellite, testing optimization), go with Ansible!**
