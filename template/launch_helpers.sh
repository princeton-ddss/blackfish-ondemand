#!/usr/bin/env bash

# This file is sourced by both the batch wrapper and the server process.
export BLACKFISH_STATUS_FILE="${PWD}/launch-status.txt"

launch_status() {
  local message="$1"
  local temporary_file="${BLACKFISH_STATUS_FILE}.tmp.$$"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message"
  printf '%s\n' "$message" > "$temporary_file" &&
    mv -f -- "$temporary_file" "$BLACKFISH_STATUS_FILE"
}

launch_fail() {
  launch_status "Failed: $1. See output.log in the session directory for details."
  exit 1
}
