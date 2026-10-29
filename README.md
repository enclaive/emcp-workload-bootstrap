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
0.0.5/
  enclaive-workload-bootstrap.tar.gz
  SHA256SUMS
```

Cloud-init should download and verify the selected version before extracting:

```bash
VERSION="0.0.5"
BASE_URL="https://github.com/enclaive/emcp-workload-bootstrap/releases/download/$VERSION"

install -d -m 0755 /enclaive-cloud-init/bootstrap
curl --fail --show-error --location "$BASE_URL/enclaive-workload-bootstrap.tar.gz" \
  --output /enclaive-cloud-init/bootstrap/enclaive-workload-bootstrap.tar.gz
curl --fail --show-error --location "$BASE_URL/SHA256SUMS" \
  --output /enclaive-cloud-init/bootstrap/SHA256SUMS
(cd /enclaive-cloud-init/bootstrap && sha256sum --check SHA256SUMS)
tar -xzf /enclaive-cloud-init/bootstrap/enclaive-workload-bootstrap.tar.gz -C /enclaive-cloud-init/bootstrap
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

## Cloud-init completion

`scripts/lib/notify-cloud-init-completion.sh` waits for `cloud-init status
--wait` and reports the outcome to the backend, so the resource (VM, database,
app, cluster node) is only activated once cloud-init has finished. It maps the
exit code to an event and sends it through `scripts/lib/webhook-events.sh`:

| `cloud-init status` exit code | Event |
|---|---|
| `0` done | `cloud-init-completed` |
| `2` done with recoverable errors (degraded) | `cloud-init-completed` with `"degraded": true` |
| anything else | `cloud-init-failed` with `"exitCode"` |

Start it detached once the bootstrap is on disk. It needs `WEBHOOK_URL` in its
environment, which comes from the rendered cloud-init configuration; keep the
URL out of this public repository and out of release artifacts:

```bash
WEBHOOK_URL="$WEBHOOK_URL" setsid -f bash \
  /enclaive-cloud-init/bootstrap/scripts/lib/notify-cloud-init-completion.sh \
  > /enclaive-cloud-init/notify-cloud-init-completion.log 2>&1
```

If `$ENCLAIVE_CLOUD_INIT_DIR/pre-completion-hook.sh` exists (default
`/enclaive-cloud-init`), it runs before a success is reported. Its failure does
not change the reported outcome.

`webhook-events.sh` can also be called directly:

```bash
WEBHOOK_URL="$WEBHOOK_URL" webhook-events.sh cloud_init_completed_event [degraded]
WEBHOOK_URL="$WEBHOOK_URL" webhook-events.sh cloud_init_failed_event [exit_code]
```

It retries up to `WEBHOOK_MAX_RETRIES` times (default 10), waiting
`WEBHOOK_RETRY_SLEEP_SECONDS` (default 30) between attempts.

Run the behavioural tests with `bash tests/notify-cloud-init-completion.test.sh`.
They need bash, curl and python3, and use a stub `cloud-init` and a local fake
webhook.
