# OCP Container Product Management for Satellite

This guide covers generating OCP container product definitions from OpenShift
release metadata and pushing them to a Satellite server.

## Overview

The workflow has two stages:

1. **Generate** — fetch an OCP release.txt, parse container image digests,
   and produce Satellite-ready configuration files
2. **Push** — create the product and repositories on Satellite using the
   `redhat.satellite` collection

These can run independently. Generate once, push to multiple Satellites.
Or generate and push in sequence for a single target.

## Prerequisites

- Ansible with the `redhat.satellite` collection installed
- An OpenShift pull secret from <https://console.redhat.com/openshift/install/pull-secret>
- Quay.io credentials extracted into a vault file (see [PULL-SECRET-SETUP.md](PULL-SECRET-SETUP.md))

### Install the Satellite collection

```bash
ansible-galaxy collection install redhat.satellite
```

Or use the provided requirements file:

```bash
ansible-galaxy install -r requirements.yml
```

### One-time credential setup

```bash
./extract-pull-secret.sh pull-secret.txt
```

This creates encrypted vault files in `group_vars/` with the `quay_registry_*`
and `redhat_registry_*` variables.

## Vault Variables

The playbooks rely on two sets of vaulted credentials stored in `group_vars/`.
These are created by the `extract-pull-secret.sh` script.

### `group_vars/vault_quay_credentials.yml`

```yaml
---
quay_registry_username_vault: "<quay.io-username>"
quay_registry_password_vault: "<quay.io-token>"
```

Used as `upstream_username` and `upstream_password` for quay.io container
repositories (OCP release and component images).

### `group_vars/vault_redhat_registry_credentials.yml`

```yaml
---
redhat_registry_username_vault: "<registry.redhat.io-username>"
redhat_registry_password_vault: "<registry.redhat.io-token>"
```

Used for Red Hat certified container image repositories. Not required for
OCP images (those come from quay.io) but available for other products.

### Vault password

Pass `--ask-vault-pass` on the command line, or configure a vault password
file in `ansible.cfg`:

```ini
[defaults]
vault_password_file = ~/.vault_pass
```

## Inventory

The `push-ocp-product.yml` playbook runs against `localhost` and connects
to Satellite via its API, so no SSH inventory is needed. The Satellite
connection details are passed as extra variables:

| Variable | Example | Description |
|---|---|---|
| `satellite_url` | `https://satellite1.example.ca` | Satellite server URL |
| `satellite_username` | `admin` | Satellite admin user |
| `satellite_password` | `changeme` | Satellite admin password |
| `satellite_organization` | `Default Organization` | Target organization |

Alternatively, these can be set in a variables file to avoid repeating them:

### `group_vars/satellite_connection.yml` (example)

```yaml
---
satellite_url: "https://satellite1.example.ca"
satellite_username: "admin"
satellite_organization: "Default Organization"
satellite_validate_certs: true
```

Then pass only the password at runtime:

```bash
ansible-playbook push-ocp-product.yml \
  -e ocp_minor=4.20 \
  -e satellite_password=changeme \
  --ask-vault-pass
```

For GSSAPI authentication (Kerberos), no username or password is needed:

```bash
ansible-playbook push-ocp-product.yml \
  -e ocp_minor=4.20 \
  -e satellite_url=https://satellite1.example.ca \
  -e satellite_use_gssapi=true \
  --ask-vault-pass
```

The `--ask-vault-pass` is still needed to decrypt the quay.io credentials.

## Stage 1: Generate Product Definition

The `generate-ocp-product.yml` playbook fetches the OCP release.txt for a
given version, parses all container image digests, and produces three files.

### Usage

```bash
ansible-playbook generate-ocp-product.yml -e ocp_version=4.20.32
```

For environments with non-blocking IO issues (e.g. running from Claude Code):

```bash
script -qc "ansible-playbook generate-ocp-product.yml -e ocp_version=4.20.32" /dev/null
```

### Parameters

| Variable | Required | Description |
|---|---|---|
| `ocp_version` | Yes | Full version in X.Y.Z format (e.g. `4.20.32`) |

### Output Files

All output goes to the `generated/` directory:

| File | Purpose |
|---|---|
| `ocp-4.20-custom-product.yml` | Product entry to merge into `custom_products.yml` |
| `ocp_420_tags.yml` | Tag lists as YAML arrays (one digest per line) |
| `ocp-4.20-repositories.yml` | Repository entries to append to `repositories.yml` |
| `ocp-4.20-versions.json` | Version tracking data for z-stream accumulation |

### Accumulating Z-stream Releases

Run the playbook multiple times with different z-stream versions to accumulate
digests into a single product per OCP minor version:

```bash
ansible-playbook generate-ocp-product.yml -e ocp_version=4.20.32
ansible-playbook generate-ocp-product.yml -e ocp_version=4.20.33
ansible-playbook generate-ocp-product.yml -e ocp_version=4.20.34
```

Each run merges new digests with existing ones. The `versions.json` file
tracks which z-streams have been included. Use content views in Satellite
to create point-in-time snapshots for specific z-stream releases.

### Using with rhis-builder-satellite

To use the generated files with rhis-builder-satellite:

1. Copy the tags file to the host_vars directory:
   ```bash
   cp generated/ocp_420_tags.yml \
     <inventory>/host_vars/<satellite-host>/
   ```

2. Merge the product entry from `ocp-4.20-custom-product.yml` into
   `custom_products.yml` — the `include_tags` fields reference the tag
   list variables via `join(',')`, keeping the file lint-friendly.

3. Append the repository entries from `ocp-4.20-repositories.yml` to
   `repositories.yml` to set download policy and mirroring policy.

## Stage 2: Push to Satellite

The `push-ocp-product.yml` playbook creates the product and repositories
directly on a Satellite server using the `redhat.satellite` collection.
This is the standalone alternative to running rhis-builder-satellite.

### Usage

Basic — create product and repositories:

```bash
ansible-playbook push-ocp-product.yml \
  -e ocp_minor=4.20 \
  -e satellite_url=https://satellite1.example.ca \
  -e satellite_username=admin \
  -e satellite_password=changeme \
  --ask-vault-pass
```

Create and immediately trigger a sync:

```bash
ansible-playbook push-ocp-product.yml \
  -e ocp_minor=4.20 \
  -e satellite_url=https://satellite1.example.ca \
  -e satellite_username=admin \
  -e satellite_password=changeme \
  -e sync_after_create=true \
  --ask-vault-pass
```

With GSSAPI authentication (no username/password needed):

```bash
ansible-playbook push-ocp-product.yml \
  -e ocp_minor=4.20 \
  -e satellite_url=https://satellite1.example.ca \
  -e satellite_use_gssapi=true \
  --ask-vault-pass
```

### Parameters

| Variable | Required | Default | Description |
|---|---|---|---|
| `ocp_minor` | Yes | — | OCP minor version (e.g. `4.20`) |
| `satellite_url` | Yes | — | Satellite server URL |
| `satellite_username` | * | — | Satellite admin username |
| `satellite_password` | * | — | Satellite admin password |
| `satellite_use_gssapi` | * | `false` | Use GSSAPI instead of username/password |
| `satellite_organization` | No | `Default Organization` | Satellite organization |
| `satellite_validate_certs` | No | `true` | Validate Satellite TLS certificate |
| `sync_after_create` | No | `false` | Trigger repository sync after creation |

\* Either `satellite_username`/`satellite_password` or `satellite_use_gssapi=true`
is required.

### What It Creates

| Resource | Details |
|---|---|
| **Product** | `OpenShift Container Platform 4.20` |
| **Repository: ocp-release** | Release images from `quay.io/openshift-release-dev/ocp-release` |
| **Repository: ocp-v4.0-art-dev** | Component images from `quay.io/openshift-release-dev/ocp-v4.0-art-dev` |

Both repositories are configured with:
- `download_policy: immediate`
- `mirroring_policy: additive` (required to preserve the bypass sync optimization)
- `include_tags` set to the sha256 digests from the generated tag file
- `exclude_tags: *-source`

## End-to-End Example

Generate the product definition for OCP 4.22.9 and push it to Satellite:

```bash
# Step 1: Generate
ansible-playbook generate-ocp-product.yml -e ocp_version=4.22.9

# Step 2: Push and sync
ansible-playbook push-ocp-product.yml \
  -e ocp_minor=4.22 \
  -e satellite_url=https://satellite1.example.ca \
  -e satellite_username=admin \
  -e satellite_password=changeme \
  -e sync_after_create=true \
  --ask-vault-pass
```

## Important Notes

### Mirroring Policy

The repositories **must** use `additive` mirroring policy. Any mirror mode
(`mirror_content_only` or `mirror_complete`) will cause the sync bypass
optimization to be skipped, resulting in significantly longer sync times.

### Pull Secret Expiration

The OpenShift pull secret from console.redhat.com does not expire.
However, regenerating it on the console revokes the previous token.

### Digest-Only Tags

The `include_tags` values are sha256 digests, not human-readable tag names.
This is intentional — the bypass sync optimization only activates for
digest-based tags, providing a 249x speedup over tag-based syncs.

## File Reference

```
ansible/
├── generate-ocp-product.yml          # Stage 1: parse release.txt, generate config
├── push-ocp-product.yml              # Stage 2: push product to Satellite via API
├── extract-pull-secret.sh            # Extract registry creds from pull-secret.txt
├── templates/
│   ├── ocp-custom-product.yml.j2     # Product entry template (join references)
│   ├── ocp-tags.yml.j2              # Tag list template (one digest per line)
│   └── ocp-repositories.yml.j2      # Repository config template
├── generated/                        # Output directory (git-ignored)
│   ├── ocp-4.20-custom-product.yml
│   ├── ocp_420_tags.yml
│   ├── ocp-4.20-repositories.yml
│   └── ocp-4.20-versions.json
├── group_vars/
│   ├── vault_quay_credentials.yml    # Vaulted quay.io creds
│   └── vault_redhat_registry_credentials.yml
├── OCP-PRODUCT-GUIDE.md              # This file
└── PULL-SECRET-SETUP.md              # Pull secret retrieval guide
```
