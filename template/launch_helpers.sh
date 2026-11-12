#!/usr/bin/env bash

# This file is sourced by both the batch wrapper and the server process.
export BLACKFISH_STATUS_FILE="${PWD}/launch-status.txt"

launch_status() {
  local entry
  printf -v entry '[%s] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
  printf '%s\n' "$entry"
  printf '%s\n' "$entry" >> "$BLACKFISH_STATUS_FILE"
}

launch_failure_recorded() {
  grep -qE '^\[[^]]+\] Failed:' "$BLACKFISH_STATUS_FILE" 2>/dev/null
}

launch_error() {
  if ! launch_failure_recorded; then
    launch_status "Failed: $1. See output.log in the session directory for details."
  fi
}

launch_fail() {
  launch_error "$1"
  exit 1
}
