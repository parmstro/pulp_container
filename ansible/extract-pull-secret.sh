#!/bin/bash
#
# Extract registry credentials from an OpenShift pull secret and write
# them to Ansible vault-encrypted variable files.
#
# Usage: ./extract-pull-secret.sh <path-to-pull-secret.txt>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUP_VARS_DIR="${SCRIPT_DIR}/group_vars"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <pull-secret.txt>"
    echo ""
    echo "Download your pull secret from:"
    echo "  https://console.redhat.com/openshift/install/pull-secret"
    exit 1
fi

PULL_SECRET="$1"

if [[ ! -f "$PULL_SECRET" ]]; then
    echo "ERROR: File not found: $PULL_SECRET"
    exit 1
fi

# Validate JSON structure
if ! jq -e '.auths' "$PULL_SECRET" > /dev/null 2>&1; then
    echo "ERROR: Invalid pull secret format — expected JSON with .auths key"
    exit 1
fi

echo "Parsing pull secret: $PULL_SECRET"
echo ""

# List available registries
echo "Available registries:"
jq -r '.auths | keys[]' "$PULL_SECRET" | while read -r reg; do
    echo "  - $reg"
done
echo ""

extract_credentials() {
    local registry="$1"
    local username_var="$2"
    local password_var="$3"
    local vault_file="$4"

    local auth_b64
    auth_b64=$(jq -r ".auths[\"${registry}\"].auth // empty" "$PULL_SECRET")

    if [[ -z "$auth_b64" ]]; then
        echo "WARNING: No credentials found for ${registry} — skipping"
        return 1
    fi

    local decoded
    decoded=$(echo "$auth_b64" | base64 -d 2>/dev/null)

    # Split on first colon — password may contain colons
    local username="${decoded%%:*}"
    local password="${decoded#*:}"

    if [[ -z "$username" || -z "$password" ]]; then
        echo "ERROR: Failed to decode credentials for ${registry}"
        return 1
    fi

    echo "Extracted ${registry} credentials:"
    echo "  Username: ${username}"
    echo "  Password: ${password:0:8}...$(echo -n "$password" | tail -c 4) (${#password} chars)"

    # Write to a temp file, then vault-encrypt it
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << VARS
---
${username_var}: "${username}"
${password_var}: "${password}"
VARS

    # Encrypt with ansible-vault
    if [[ -f "$vault_file" ]]; then
        echo "  Existing vault file found — overwriting: $vault_file"
    fi

    ansible-vault encrypt "$tmpfile" --output="$vault_file"
    rm -f "$tmpfile"

    echo "  Wrote vault file: $vault_file"
    echo ""
}

mkdir -p "$GROUP_VARS_DIR"

# Extract quay.io credentials
extract_credentials \
    "quay.io" \
    "quay_registry_username_vault" \
    "quay_registry_password_vault" \
    "${GROUP_VARS_DIR}/vault_quay_credentials.yml"

# Extract registry.redhat.io credentials
extract_credentials \
    "registry.redhat.io" \
    "redhat_registry_username_vault" \
    "redhat_registry_password_vault" \
    "${GROUP_VARS_DIR}/vault_redhat_registry_credentials.yml"

echo "========================================"
echo "Done. Verify with:"
echo "  ansible-vault view ${GROUP_VARS_DIR}/vault_quay_credentials.yml"
echo "  ansible-vault view ${GROUP_VARS_DIR}/vault_redhat_registry_credentials.yml"
echo "========================================"
