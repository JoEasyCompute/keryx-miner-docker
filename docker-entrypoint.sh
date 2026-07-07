#!/usr/bin/env sh
set -eu

if [ "${1:-}" = "keryx-miner" ]; then
  shift
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "help" ]; then
  exec keryx-miner --help
fi

if [ "${1:-}" != "" ]; then
  exec keryx-miner "$@"
fi

if [ -z "${MINING_ADDRESS:-}" ]; then
  echo "MINING_ADDRESS is required, for example: keryx:YOUR_ADDRESS" >&2
  echo "Pass extra miner flags with KERYX_EXTRA_ARGS, or provide a full command after the image name." >&2
  exit 64
fi

mkdir -p /data/models

keryx-gpu-tune

set -- \
  --mining-address "$MINING_ADDRESS" \
  --escrow-key-file "${KERYX_ESCROW_KEY_FILE:-/data/escrow.key}" \
  --escrow-state-file "${KERYX_ESCROW_STATE_FILE:-/data/escrow_state.json}"

if [ "${KERYX_NO_OPOI:-}" = "1" ] || [ "${KERYX_NO_OPOI:-}" = "true" ]; then
  echo "KERYX_NO_OPOI is not supported by keryx-miner v0.3.5-OPoI; this release has no --no-opoi flag." >&2
  exit 64
fi

if [ -n "${KERYXD_ADDRESS:-}" ]; then
  set -- "$@" --keryxd-address "$KERYXD_ADDRESS"
fi

if [ -n "${KERYXD_PORT:-}" ]; then
  set -- "$@" --port "$KERYXD_PORT"
fi

if [ -n "${KERYX_INFERENCE_TIER:-}" ]; then
  case "$KERYX_INFERENCE_TIER" in
    light|high|very-high)
      set -- "$@" "--$KERYX_INFERENCE_TIER"
      ;;
    default)
      ;;
    *)
      echo "Unsupported KERYX_INFERENCE_TIER: $KERYX_INFERENCE_TIER" >&2
      echo "Use one of: default, light, high, very-high" >&2
      exit 64
      ;;
  esac
fi

if [ -n "${KERYX_EXTRA_ARGS:-}" ]; then
  # Deliberately supports simple shell-style extra flags such as:
  # KERYX_EXTRA_ARGS="--devfund-percent 2.0"
  # Do not put untrusted text in this variable.
  # shellcheck disable=SC2086
  set -- "$@" $KERYX_EXTRA_ARGS
fi

exec keryx-miner "$@"
