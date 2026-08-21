# Tag List Bypass Optimization

## Overview

This optimization significantly improves sync performance for deep container repositories (like OCP ART on Quay.io) when syncing a small, specific set of tags or digests.

## Problem Statement

When syncing from repositories with tens of thousands of tags:
- The `/v2/{repo}/tags/list` endpoint must be paginated (50-100 tags per page)
- **Pagination is serial** - each page must complete before requesting the next
- For a repo with 50,000 tags: 1,000 sequential HTTP requests
- Time cost: 3-8 minutes just to fetch the tag list
- Rate limiting risk: 1,000 requests in quick succession

**Example**: Syncing 10 specific OCP release tags from a 50,000-tag repository still fetches all 50,000 tags.

## Solution

When conditions allow, **bypass `/tags/list` entirely** and sync manifests directly from the `includes` list.

### When Bypass Activates

The optimization activates when ALL of these conditions are met:

1. ✅ `includes` field is populated (we know what to sync)
2. ✅ `excludes` field is empty (no negative filtering needed)
3. ✅ No wildcards in `includes` (no `*`, `?`, `[` characters)
4. ✅ Not in mirror mode (mirror requires full tag list to detect upstream deletions)

### Performance Improvement

**Before** (traditional path):
- 1,000 paginated `/tags/list` requests (serial)
- ~3-8 minutes for tag enumeration
- Then manifest processing

**After** (bypass path):
- 0 `/tags/list` requests
- 10 manifest requests (for 10 tags)
- 40-80 HEAD requests for cosign discovery (parallelized)
- Total time: **~3-5 seconds** (50-100x faster)

## Implementation Details

### New Model Field

```python
class ContainerRemote:
    auto_discover_cosign = models.BooleanField(default=True)
```

Controls whether cosign companion tags (.sig, .att, .sbom) are automatically discovered via HEAD probing when bypassing `/tags/list`.

### New Methods in `ContainerFirstStage`

1. **`_can_bypass_taglist()`**
   - Checks if bypass conditions are met
   - Returns `True` if safe to skip tag list fetch

2. **`_tag_exists(tag_name)`**
   - Lightweight HEAD request to check tag existence
   - Used for cosign companion discovery

3. **`_discover_cosign_companions_without_taglist(synced_digests)`**
   - Probes for cosign companion tags via HEAD requests
   - Checks patterns: `sha256-<digest>.{sig,att,sbom}` and `sha256-<digest>`
   - Respects concurrency limits (20 concurrent requests via semaphore)
   - Quay.io friendly (minimal rate limit impact)

### Modified Methods

1. **`ContainerFirstStage.__init__()`**
   - Now accepts `mirror` parameter to check mirror mode

2. **`ContainerFirstStage.run()`**
   - Checks `_can_bypass_taglist()` before fetching tag list
   - Bypass path: uses `includes` directly, discovers cosign via HEAD probing
   - Original path: unchanged behavior for backward compatibility

3. **`synchronize()`**
   - Passes `mirror` parameter to `ContainerFirstStage`

## Cosign Companion Tag Handling

### Auto-Discovery (default: `auto_discover_cosign=True`)

When bypassing tag list, the system probes for cosign signatures:

**V2 Cosign patterns:**
- `sha256-<digest>.sig` (signature)
- `sha256-<digest>.att` (attestation)
- `sha256-<digest>.sbom` (software bill of materials)

**V3 Cosign pattern:**
- `sha256-<digest>` (exactly 71 characters, verified as OCI index with `artifactType`)

**Probing strategy:**
1. For each synced manifest digest
2. HEAD request for each pattern (4 patterns × N manifests)
3. Concurrent execution with semaphore (20 max concurrent)
4. Verification for V3 candidates (download manifest to confirm it's cosign)

**Cost**: 40-80 HEAD requests for 10 manifests (~2-4 seconds)

### Explicit Mode (`auto_discover_cosign=False`)

When disabled, only cosign tags explicitly listed in `includes` are synced.

**Use case**: Maximum performance when signatures aren't needed or are explicitly managed.

## Migration

### Database Migration

```
0051_containerremote_auto_discover_cosign.py
```

Adds `auto_discover_cosign` field with default `True` for backward compatibility.

### Backward Compatibility

- ✅ Default behavior unchanged (fetches full tag list when conditions aren't met)
- ✅ Existing remotes get `auto_discover_cosign=True` (maintains signature sync behavior)
- ✅ Mirror mode still works as before (bypass doesn't activate)
- ✅ Wildcard includes still work (bypass doesn't activate)

## Usage Examples

### Example 1: Fast Specific Tag Sync (Bypass Active)

```python
remote = ContainerRemote.objects.create(
    name="ocp-art-fast",
    url="https://quay.io",
    upstream_name="openshift-release-dev/ocp-v4.0-art-dev",
    includes=[
        "4.12.0-x86_64",
        "4.12.1-x86_64",
        "4.12.2-x86_64",
    ],
    excludes=None,  # Must be empty
    auto_discover_cosign=True,  # Auto-discover signatures
)

# Result: Bypasses /tags/list, syncs in ~3-5 seconds
# Automatically discovers and syncs cosign signatures
```

### Example 2: Maximum Performance (No Cosign Discovery)

```python
remote = ContainerRemote.objects.create(
    name="ocp-art-fastest",
    url="https://quay.io",
    upstream_name="openshift-release-dev/ocp-v4.0-art-dev",
    includes=["4.12.0-x86_64"],
    excludes=None,
    auto_discover_cosign=False,  # Skip cosign discovery
)

# Result: Absolute minimum requests, fastest possible sync
# Only syncs what's explicitly in includes
```

### Example 3: Traditional Path (Bypass Inactive - Wildcards)

```python
remote = ContainerRemote.objects.create(
    name="ocp-art-wildcard",
    url="https://quay.io",
    upstream_name="openshift-release-dev/ocp-v4.0-art-dev",
    includes=["4.12.*"],  # Wildcard present
    excludes=None,
)

# Result: Uses original path, fetches full /tags/list
# Bypass doesn't activate due to wildcard
```

### Example 4: Mirror Mode (Bypass Inactive)

```python
# When syncing with mirror=True
synchronize(remote_pk, repository_pk, mirror=True, signed_only=False)

# Result: Uses original path, fetches full /tags/list
# Bypass doesn't activate in mirror mode (need full list to detect deletions)
```

## Testing Recommendations

### Unit Tests

1. **Bypass detection logic**
   - Test `_can_bypass_taglist()` with various includes/excludes combinations
   - Test wildcard detection (`*`, `?`, `[`)
   - Test mirror mode check

2. **Cosign discovery**
   - Mock HEAD requests for pattern probing
   - Test V2 and V3 cosign pattern detection
   - Test concurrency control (semaphore)

3. **Integration**
   - Verify bypass path executes when conditions met
   - Verify original path executes when conditions not met
   - Verify cosign tags are discovered correctly

### Functional Tests

1. **Performance test**: Sync 10 tags from a 10,000+ tag repo
   - Measure time with bypass vs without
   - Expected: 50-100x speedup

2. **Cosign test**: Verify signatures sync correctly
   - Sync image with cosign signatures
   - Verify `.sig`, `.att`, `.sbom` companions are discovered and synced

3. **Mirror mode test**: Verify mirror mode still works
   - Sync with mirror=True
   - Verify deleted upstream tags are removed locally

## Monitoring & Logging

New log messages added:

```
INFO: Bypassing /tags/list enumeration - syncing N explicit references directly
INFO: Auto-discovering cosign companion tags via HEAD probing
INFO: Found N cosign companion tag(s) for synced manifests
INFO: Syncing N explicit cosign tag(s) (auto-discovery disabled)
```

Watch for these in sync logs to confirm bypass activation.

## Limitations & Considerations

1. **Bypass only for concrete references**: Wildcards disable the optimization
2. **Mirror mode incompatible**: Mirror sync always uses traditional path
3. **Excludes incompatible**: Any excludes disable the optimization
4. **Rate limiting**: HEAD probing adds 4×N requests (still much less than 1,000-page pagination)
5. **Registry compatibility**: Assumes standard OCI registry behavior

## Future Enhancements

Potential improvements:

1. **Configurable concurrency**: Make semaphore limit adjustable per remote
2. **Selective pattern probing**: Only probe for `.sig` if user needs signatures
3. **Cache HEAD results**: Reduce redundant probes across syncs
4. **Registry-specific optimizations**: Special handling for Quay.io, GCR, etc.

## References

- Original issue: OCP ART repo sync performance (50,000+ tags)
- Quay.io rate limits: ~5,000 anonymous / higher for authenticated
- Cosign specification: https://github.com/sigstore/cosign
- OCI registry API: https://github.com/opencontainers/distribution-spec
