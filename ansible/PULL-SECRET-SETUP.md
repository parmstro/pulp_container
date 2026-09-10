# Setting Up Registry Pull Secrets for OCP Container Sync

Syncing OCP container images from quay.io requires credentials from your
Red Hat OpenShift pull secret. This document covers retrieving the pull secret
and extracting the registry credentials into Ansible vault files.

## Prerequisites

- A Red Hat account with an active OpenShift subscription
- `ansible-vault` installed
- `jq` and `base64` (standard on RHEL)

## Step 1: Download Your Pull Secret

1. Go to <https://console.redhat.com/openshift/install/pull-secret>
2. Click **Download pull secret** to save `pull-secret.txt`
3. Copy the file to this directory (or any accessible path)

The pull secret is a JSON file containing base64-encoded credentials for
multiple registries (quay.io, registry.redhat.io, registry.connect.redhat.com,
etc.).

**Important:** The pull secret does not expire. However, if you regenerate it
on console.redhat.com, the previous token is revoked. Keep it in a secure
location and never commit it to version control.

## Step 2: Extract Credentials

Run the extraction script to parse the pull secret and create vault-encrypted
variable files:

```bash
# Extract quay.io credentials (for OCP container syncs)
./extract-pull-secret.sh pull-secret.txt

# You will be prompted for your Ansible vault password
```

This creates:
- `group_vars/vault_quay_credentials.yml` — encrypted vault file with
  `quay_registry_username_vault` and `quay_registry_password_vault`
- `group_vars/vault_redhat_registry_credentials.yml` — encrypted vault file
  with `redhat_registry_username_vault` and `redhat_registry_password_vault`

## Step 3: Verify

```bash
ansible-vault view group_vars/vault_quay_credentials.yml
```

You should see:
```yaml
quay_registry_username_vault: "<your-username>"
quay_registry_password_vault: "<your-token>"
```

## Pull Secret JSON Structure

The pull secret follows the Docker/OCI auth config format:

```json
{
  "auths": {
    "quay.io": {
      "auth": "<base64(username:password)>",
      "email": "user@example.com"
    },
    "registry.redhat.io": {
      "auth": "<base64(username:password)>"
    }
  }
}
```

The `auth` field is a base64-encoded string of `username:password`. The
extraction script decodes this and splits on the first colon to separate
the username from the password/token.

## Using Credentials in rhis-builder-satellite

The vault variables are referenced in `custom_products.yml` as:

```yaml
upstream_username: "{{ quay_registry_username_vault }}"
upstream_password: "{{ quay_registry_password_vault }}"
```

When deploying via rhis-provisioner, pass `--ask-vault-pass` or configure
a vault password file.

## Registries in the Pull Secret

| Registry | Variable Prefix | Used For |
|---|---|---|
| quay.io | `quay_registry_*` | OCP release and component images |
| registry.redhat.io | `redhat_registry_*` | Red Hat certified container images |
| registry.connect.redhat.com | (same as registry.redhat.io) | Partner/ISV containers |

## Troubleshooting

**Sync fails with 401 Unauthorized:**
Re-download the pull secret from console.redhat.com. If you regenerated
it recently, the old token is revoked.

**Username looks like an email address:**
This is normal for quay.io — the username from the pull secret is typically
a service account identifier or email, not a human-readable name.

**Token works with podman but not Satellite:**
Satellite needs the decoded username and password separately, not the
base64-encoded `auth` string. The extraction script handles this decoding.
