# Enclaive Workload Bootstrap

Reusable shell snippets for Enclaive workload provisioning and snapshot
restoration. The repository is public: do not add credentials, Vault tokens,
tenant identifiers, generated domains, or private service addresses.

## Layout

```text
scripts/
  lib/          Shared shell helpers
  nextcloud/    Nextcloud provisioning and restore helpers
  database/     Database provisioning and restore helpers
  opendesk/     OpenDesk provisioning and restore helpers
manifests/      Release manifests and checksums
tests/shellcheck/ ShellCheck fixtures and tests
.github/workflows/ Release automation
```

## Nextcloud domain reconciliation

`scripts/nextcloud/configure-domain.sh` defines
`configure_nextcloud_domain`. Source it from the workload bootstrap after
defining `DOMAIN_NAME` and `echo_message`, then call the function after the
Nextcloud container starts:

```bash
DOMAIN_NAME="nextcloud.example.com"

echo_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] bootstrap: $1"
}

source /enclaive-cloud-init/bootstrap/scripts/nextcloud/configure-domain.sh
docker compose up -d
configure_nextcloud_domain
```

The helper waits for `occ`, then updates the persisted Nextcloud configuration
for the restored domain. This is required because the official image applies
`NEXTCLOUD_TRUSTED_DOMAINS` only during initial installation.

## Releases

Consume immutable release artifacts, never a mutable branch. A release should
contain a tarball and `SHA256SUMS`, for example:

```text
0.0.2/
  enclaive-workload-bootstrap.tar.gz
  SHA256SUMS
```

Cloud-init should download and verify the selected version before extracting:

```bash
VERSION="0.0.2"
BASE_URL="https://github.com/enclaive/emcp-workload-bootstrap/releases/download/$VERSION"

install -d -m 0755 /enclaive-cloud-init/bootstrap
curl --fail --show-error --location "$BASE_URL/enclaive-workload-bootstrap.tar.gz" \
  --output /enclaive-cloud-init/bootstrap/bootstrap.tar.gz
curl --fail --show-error --location "$BASE_URL/SHA256SUMS" \
  --output /enclaive-cloud-init/bootstrap/SHA256SUMS
(cd /enclaive-cloud-init/bootstrap && sha256sum --check SHA256SUMS)
tar -xzf /enclaive-cloud-init/bootstrap/bootstrap.tar.gz -C /enclaive-cloud-init/bootstrap
```

Pushing a Git tag runs the release workflow, which creates a draft release,
packages `scripts/`, writes `SHA256SUMS`, uploads both files, and then publishes
the release. This draft-first order is required because published releases are
immutable. Create a draft release first, then use **Actions → Release bootstrap
bundle → Run workflow** with its release tag to publish its assets. A published
immutable release with missing assets must be deleted and recreated before
running the workflow.

Runtime configuration and secrets must remain in the workload's vHSM/Vault
rendered files. Scripts may read those files but must not embed their contents.
