#!/usr/bin/env bash
# shellcheck shell=bash

# Send lifecycle events to the workload webhook. The caller provides WEBHOOK_URL
# so release artifacts never contain workload-specific endpoints.

trigger_webhook_event() {
  local payload="$1"
  local max_retries=10
  local retry_count=0
  local sleep_time=30
  local response

  while [ "$retry_count" -lt "$max_retries" ]; do
    response=$(curl --silent --output /dev/null --write-out '%{http_code}' \
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
  installation_completed_event)
    trigger_webhook_event '{"type":"installation-completed"}'
    ;;
  installation_failed_event)
    trigger_webhook_event '{"type":"installation-failed"}'
    ;;
  *)
    echo "Unknown event type: ${1:-}" >&2
    exit 2
    ;;
esac
