#!/usr/bin/env bash
# shellcheck shell=bash

# Reconcile Nextcloud's persisted public-domain settings after a snapshot
# restore. Source this file after defining echo_message and DOMAIN_NAME.
configure_nextcloud_domain() {
  local max_retries=150
  local retry=0

  # `occ status` exits successfully before initial installation and reports
  # `installed: false`. Wait for the completed installation, not merely for
  # the container to accept an `occ` command.
  until docker exec --user www-data nextcloud php occ status --output=json 2>/dev/null | \
    jq -e '.installed == true' >/dev/null 2>&1; do
    retry=$((retry + 1))
    if [ "$retry" -ge "$max_retries" ]; then
      echo_message "Nextcloud did not become ready to update its public domain"
      return 1
    fi
    sleep 2
  done

  # The image only applies NEXTCLOUD_TRUSTED_DOMAINS during its initial
  # installation. A restored data volume keeps the source config.php, so
  # replace its public-domain settings after the container is ready.
  docker exec --user www-data nextcloud php occ config:system:set trusted_domains 1 --value="$DOMAIN_NAME"
  docker exec --user www-data nextcloud php occ config:system:set overwritehost --value="$DOMAIN_NAME"
  docker exec --user www-data nextcloud php occ config:system:set overwriteprotocol --value="https"
  docker exec --user www-data nextcloud php occ config:system:set overwrite.cli.url --value="https://$DOMAIN_NAME"
}
