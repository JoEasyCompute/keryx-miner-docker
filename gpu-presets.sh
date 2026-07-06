#!/usr/bin/env sh

# Presets intentionally avoid GPU-model-specific absolute clocks. Those are
# rig-specific and unsafe to guess. Override any value in .env.
case "${KERYX_GPU_PRESET:-none}" in
  none|custom|"")
    ;;
  efficiency)
    : "${KERYX_GPU_POWER_LIMIT_PERCENT:=70}"
    ;;
  balanced)
    : "${KERYX_GPU_POWER_LIMIT_PERCENT:=85}"
    ;;
  performance)
    : "${KERYX_GPU_POWER_LIMIT_PERCENT:=100}"
    ;;
  *)
    echo "Unsupported KERYX_GPU_PRESET: ${KERYX_GPU_PRESET}" >&2
    echo "Use one of: none, custom, efficiency, balanced, performance" >&2
    exit 64
    ;;
esac

export KERYX_GPU_POWER_LIMIT_PERCENT
