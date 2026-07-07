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
  echo "KERYX_NO_OPOI is not supported by this keryx-miner OPoI release; there is no --no-opoi flag." >&2
  exit 64
fi

keryxd_port_from_url=""

if [ -n "${KERYX_NODE_URL:-}" ]; then
  case "$KERYX_NODE_URL" in
    grpc://*)
      keryxd_endpoint="${KERYX_NODE_URL#grpc://}"
      case "$keryxd_endpoint" in
        *:*)
          keryxd_host="${keryxd_endpoint%:*}"
          keryxd_port_from_url="${keryxd_endpoint##*:}"
          if [ -z "$keryxd_host" ] || [ -z "$keryxd_port_from_url" ]; then
            echo "Invalid KERYX_NODE_URL: $KERYX_NODE_URL" >&2
            exit 64
          fi
          set -- "$@" --keryxd-address "$keryxd_host"
          ;;
        *)
          set -- "$@" --keryxd-address "$keryxd_endpoint"
          ;;
      esac
      ;;
    *)
      set -- "$@" --keryxd-address "$KERYX_NODE_URL"
      ;;
  esac
elif [ -n "${KERYX_POOL_HOST:-}" ]; then
  if [ -z "${KERYX_POOL_PORT:-}" ]; then
    echo "KERYX_POOL_PORT is required when KERYX_POOL_HOST is set." >&2
    exit 64
  fi
  set -- "$@" --keryxd-address "stratum+tcp://${KERYX_POOL_HOST}:${KERYX_POOL_PORT}"
elif [ -n "${KERYXD_ADDRESS:-}" ]; then
  set -- "$@" --keryxd-address "$KERYXD_ADDRESS"
elif [ "${KERYX_ALLOW_LOCAL_KERYXD_DEFAULT:-}" = "1" ] || [ "${KERYX_ALLOW_LOCAL_KERYXD_DEFAULT:-}" = "true" ]; then
  :
else
  echo "Keryx endpoint is required in Docker." >&2
  echo "Set KERYX_NODE_URL to grpc://HOST:22110 or stratum+tcp://POOL:PORT." >&2
  echo "Alternatively set KERYXD_ADDRESS/KERYXD_PORT or KERYX_POOL_HOST/KERYX_POOL_PORT." >&2
  echo "Use KERYX_ALLOW_LOCAL_KERYXD_DEFAULT=true only if keryxd runs inside this same container." >&2
  exit 64
fi

if [ -n "${KERYXD_PORT:-}" ]; then
  set -- "$@" --port "$KERYXD_PORT"
elif [ -n "$keryxd_port_from_url" ]; then
  set -- "$@" --port "$keryxd_port_from_url"
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
