#!/usr/bin/env bash
# shellcheck shell=bash

# Wait for the public workload name to resolve before a service such as
# Let's Encrypt validates it. Source this file after defining echo_message.
wait_for_domain() {
  local domain="$1"
  local resolved_ips
  local attempt

  for attempt in $(seq 1 120); do
    resolved_ips=$(getent ahostsv4 "$domain" 2>/dev/null | \
      awk '{ print $1 }' | sort -u || true)
    if [ -n "$resolved_ips" ]; then
      echo_message "$domain resolves to: $resolved_ips"
      return 0
    fi

    echo_message "Waiting for $domain to resolve (attempt $attempt/120)."
    sleep 10
  done

  echo_message "$domain did not resolve within 20 minutes."
  return 1
}
