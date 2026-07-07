#!/usr/bin/env sh
set -eu

if [ "${1:-}" = "keryxd" ]; then
  shift
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "help" ]; then
  exec keryxd --help
fi

if [ "${1:-}" != "" ]; then
  exec keryxd "$@"
fi

if [ -n "${KERYXD_EXTRA_ARGS:-}" ]; then
  # Deliberately supports simple shell-style flags only.
  # Do not put untrusted text in this variable.
  # shellcheck disable=SC2086
  set -- $KERYXD_EXTRA_ARGS
fi

exec keryxd "$@"
