#!/usr/bin/env bash
# shellcheck shell=bash

# Send lifecycle events to the workload webhook. The caller provides WEBHOOK_URL
# so release artifacts never contain workload-specific endpoints.
#
# Usage:
#   webhook-events.sh cloud_init_completed_event [degraded]
#   webhook-events.sh cloud_init_failed_event [exit_code]
#
# WEBHOOK_MAX_RETRIES and WEBHOOK_RETRY_SLEEP_SECONDS override the retry policy.

trigger_webhook_event() {
  local payload="$1"
  local max_retries="${WEBHOOK_MAX_RETRIES:-10}"
  local sleep_time="${WEBHOOK_RETRY_SLEEP_SECONDS:-30}"
  local retry_count=0
  local response

  while [ "$retry_count" -lt "$max_retries" ]; do
    response=$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --connect-timeout 10 --max-time 30 \
      --request POST "$WEBHOOK_URL" \
      --header 'Content-Type: application/json' \
      --data "$payload")

    if [ "$response" = '200' ]; then
      echo 'Webhook request successful.'
      return 0
    fi

    retry_count=$((retry_count + 1))
    if [ "$retry_count" -lt "$max_retries" ]; then
      echo "Webhook request failed with status $response. Retrying in $sleep_time seconds..."
      sleep "$sleep_time"
    fi
  done

  echo "Webhook request failed after $max_retries attempts."
  return 1
}

case "${1:-}" in
  cloud_init_completed_event)
    if [ "${2:-}" = 'degraded' ]; then
      trigger_webhook_event '{"type":"cloud-init-completed","degraded":true}'
    else
      trigger_webhook_event '{"type":"cloud-init-completed"}'
    fi
    ;;
  cloud_init_failed_event)
    case "${2:-}" in
      '')
        trigger_webhook_event '{"type":"cloud-init-failed"}'
        ;;
      *[!0-9]*)
        echo "Invalid cloud-init exit code: $2" >&2
        exit 2
        ;;
      *)
        trigger_webhook_event "{\"type\":\"cloud-init-failed\",\"exitCode\":$2}"
        ;;
    esac
    ;;
  *)
    echo "Unknown event type: ${1:-}" >&2
    exit 2
    ;;
esac
