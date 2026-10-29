#!/usr/bin/env bash
# shellcheck shell=bash

# Wait for cloud-init to finish and report the outcome to the backend so the
# resource can be activated. Shared by every resource type (VM, database, app,
# cluster node); the endpoint comes from WEBHOOK_URL at runtime.
#
# Start it detached once the bootstrap is on disk, for example:
#   WEBHOOK_URL='...' setsid -f bash "$BOOTSTRAP_DIR/scripts/lib/notify-cloud-init-completion.sh" \
#     > /enclaive-cloud-init/notify-cloud-init-completion.log 2>&1
#
# cloud-init status --wait exit codes: 0 done, 1 error, 2 done with recoverable
# errors (degraded, reported as success).
#
# Optional: $ENCLAIVE_CLOUD_INIT_DIR/pre-completion-hook.sh runs before a success
# is reported (override with PRE_COMPLETION_HOOK). Its failure does not change
# the reported outcome.

set -u

: "${WEBHOOK_URL:?WEBHOOK_URL must be set}"
export WEBHOOK_URL

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cloud_init_dir="${ENCLAIVE_CLOUD_INIT_DIR:-/enclaive-cloud-init}"
pre_completion_hook="${PRE_COMPLETION_HOOK:-$cloud_init_dir/pre-completion-hook.sh}"

cloud-init status --wait > /dev/null 2>&1
code=$?

case "$code" in
  0)
    event_args=(cloud_init_completed_event)
    ;;
  2)
    echo 'cloud-init finished with recoverable errors (degraded); reporting success.'
    event_args=(cloud_init_completed_event degraded)
    ;;
  *)
    echo "cloud-init failed with exit code $code."
    event_args=(cloud_init_failed_event "$code")
    ;;
esac

if [ "${event_args[0]}" = 'cloud_init_completed_event' ] && [ -x "$pre_completion_hook" ]; then
  "$pre_completion_hook" || echo "Pre-completion hook failed with status $?."
fi

exec bash "$script_dir/webhook-events.sh" "${event_args[@]}"
