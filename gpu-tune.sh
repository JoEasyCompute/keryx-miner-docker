#!/usr/bin/env sh
set -eu

warn() {
  echo "gpu-tune: $*" >&2
}

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

fail_or_warn() {
  if is_true "${KERYX_GPU_TUNING_STRICT:-false}"; then
    echo "gpu-tune: $*" >&2
    exit 70
  fi

  warn "$*"
}

is_enabled() {
  is_true "${KERYX_GPU_TUNING:-false}" \
    || is_true "${KERYX_GPU_PRESETS_ENABLE:-false}" \
    || [ -n "${KERYX_GPU_PRESETS_URL:-}" ]
}

trim() {
  value="$1"
  value="${value#"${value%%[!	 ]*}"}"
  value="${value%"${value##*[!	 ]}"}"
  printf '%s' "$value"
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

gpu_devices() {
  if [ -n "${KERYX_GPU_DEVICES:-}" ] && [ "${KERYX_GPU_DEVICES}" != "all" ]; then
    echo "$KERYX_GPU_DEVICES" | tr ',' ' '
    return
  fi

  if [ -n "${NVIDIA_VISIBLE_DEVICES:-}" ] && [ "${NVIDIA_VISIBLE_DEVICES}" != "all" ] && [ "${NVIDIA_VISIBLE_DEVICES}" != "void" ]; then
    echo "$NVIDIA_VISIBLE_DEVICES" | tr ',' ' '
    return
  fi

  nvidia-smi --query-gpu=index --format=csv,noheader,nounits | tr '\n' ' '
}

clock_range() {
  value="$1"
  case "$value" in
    *:*)
      printf '%s' "$value" | tr ':' ','
      ;;
    *)
      printf '%s,%s' "$value" "$value"
      ;;
  esac
}

default_power_limit() {
  gpu="$1"
  nvidia-smi -i "$gpu" --query-gpu=power.default_limit --format=csv,noheader,nounits \
    | awk '{ printf "%d\n", $1 }'
}

percent_power_limit() {
  gpu="$1"
  percent="$2"
  default_limit="$(default_power_limit "$gpu")"
  awk -v watts="$default_limit" -v percent="$percent" 'BEGIN { printf "%d\n", watts * percent / 100 }'
}

run_setting() {
  description="$1"
  shift

  if is_true "${KERYX_GPU_PRESETS_DRY_RUN:-false}"; then
    warn "DRY RUN: ${description}: $*"
    return 0
  fi

  "$@" || fail_or_warn "failed ${description}: $*"
}

apply_nvidia_settings_offsets() {
  gpu="$1"
  core_offset="${2:-${KERYX_GPU_CORE_CLOCK_OFFSET:-}}"
  memory_offset="${3:-${KERYX_GPU_MEMORY_CLOCK_OFFSET:-}}"
  fan_speed="${4:-}"

  if ! is_true "${KERYX_GPU_USE_NVIDIA_SETTINGS:-false}"; then
    if [ -n "$core_offset" ] || [ -n "$memory_offset" ] || [ -n "$fan_speed" ]; then
      warn "clock offsets requested but not applied; set KERYX_GPU_USE_NVIDIA_SETTINGS=true only on hosts with X/NV-CONTROL Coolbits exposed"
    fi
    return
  fi

  if ! command -v nvidia-settings >/dev/null 2>&1; then
    fail_or_warn "nvidia-settings is not installed; cannot apply clock offsets"
    return
  fi

  if [ -n "$core_offset" ]; then
    run_setting "GPU ${gpu} core clock offset ${core_offset}MHz" \
      nvidia-settings -a "[gpu:${gpu}]/GPUGraphicsClockOffsetAllPerformanceLevels=${core_offset}"
  fi

  if [ -n "$memory_offset" ]; then
    run_setting "GPU ${gpu} memory clock offset ${memory_offset}MHz" \
      nvidia-settings -a "[gpu:${gpu}]/GPUMemoryTransferRateOffsetAllPerformanceLevels=${memory_offset}"
  fi

  if [ -n "$fan_speed" ]; then
    run_setting "GPU ${gpu} fan speed ${fan_speed}%" \
      nvidia-settings -a "[gpu:${gpu}]/GPUFanControlState=1" -a "[fan:${gpu}]/GPUTargetFanSpeed=${fan_speed}"
  fi
}

fetch_preset_file() {
  preset_file="${KERYX_GPU_PRESETS_FILE:-/etc/keryx/gpu-presets.csv}"
  timeout="${KERYX_GPU_PRESETS_TIMEOUT:-10}"

  case "$timeout" in
    *[!0-9]*|"")
      warn "KERYX_GPU_PRESETS_TIMEOUT must be an integer; using 10 seconds"
      timeout=10
      ;;
  esac

  if [ -n "${KERYX_GPU_PRESETS_URL:-}" ]; then
    if ! command -v curl >/dev/null 2>&1; then
      fail_or_warn "curl is unavailable; cannot fetch ${KERYX_GPU_PRESETS_URL}"
      return 1
    fi

    preset_file="/tmp/keryx-gpu-presets.csv"
    warn "fetching GPU presets from ${KERYX_GPU_PRESETS_URL}"
    curl -fsSL --max-time "$timeout" "${KERYX_GPU_PRESETS_URL}" -o "$preset_file" \
      || {
        fail_or_warn "failed to fetch GPU presets from ${KERYX_GPU_PRESETS_URL}"
        return 1
      }
  fi

  if [ -n "${KERYX_GPU_PRESETS_SHA256:-}" ]; then
    echo "${KERYX_GPU_PRESETS_SHA256}  ${preset_file}" | sha256sum -c - >/dev/null \
      || {
        fail_or_warn "GPU preset file checksum mismatch"
        return 1
      }
    warn "verified GPU preset checksum"
  fi

  if [ ! -f "$preset_file" ]; then
    fail_or_warn "GPU preset file not found: ${preset_file}"
    return 1
  fi

  if [ ! -s "$preset_file" ]; then
    fail_or_warn "GPU preset file is empty: ${preset_file}"
    return 1
  fi

  resolved_preset_file="$preset_file"
  return 0
}

find_csv_preset_for_gpu() {
  preset_file="$1"
  gpu_name_lc="$2"
  algorithm="$(lower "$(trim "${KERYX_GPU_PRESETS_ALGORITHM:-keryx}")")"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%}"
    [ -n "$(trim "$line")" ] || continue
    case "$(trim "$line")" in
      \#*) continue ;;
    esac
    [ "$(lower "$(trim "$line")")" = "enabled,algorithm,gpu_name_contains,power_limit_w,lock_core_clock_mhz,core_clock_offset_mhz,lock_memory_clock_mhz,memory_clock_offset_mhz,fan_speed_pct,delay_before_apply_s" ] && continue

    IFS=',' read -r enabled row_algorithm matcher power_limit_w lock_core_clock_mhz core_clock_offset_mhz lock_memory_clock_mhz memory_clock_offset_mhz fan_speed_pct delay_before_apply_s extra <<EOF
$line
EOF

    if [ -n "${extra:-}" ]; then
      warn "skipping CSV row with too many fields: ${line}"
      continue
    fi

    enabled="$(lower "$(trim "${enabled:-}")")"
    row_algorithm="$(lower "$(trim "${row_algorithm:-}")")"
    matcher="$(lower "$(trim "${matcher:-}")")"

    case "$enabled" in
      true|1|yes) ;;
      *) continue ;;
    esac

    [ -z "$row_algorithm" ] || [ "$row_algorithm" = "$algorithm" ] || continue
    [ -n "$matcher" ] || continue

    case "$gpu_name_lc" in
      *"$matcher"*)
        printf '%s\n' "$line"
        return 0
        ;;
    esac
  done <"$preset_file"

  return 1
}

validate_integer() {
  name="$1"
  value="$2"
  signed="${3:-false}"

  if is_true "$signed"; then
    case "$value" in
      -[0-9]*|[0-9]*)
        unsigned="${value#-}"
        case "$unsigned" in
          *[!0-9]*|"") warn "invalid ${name}: ${value}"; return 1 ;;
        esac
        ;;
      *) warn "invalid ${name}: ${value}"; return 1 ;;
    esac
  else
    case "$value" in
      *[!0-9]*|"") warn "invalid ${name}: ${value}"; return 1 ;;
      *) ;;
    esac
  fi

  return 0
}

validate_clock_value() {
  name="$1"
  value="$2"

  case "$value" in
    *:*)
      min_clock="${value%%:*}"
      max_clock="${value#*:}"
      validate_integer "${name}_min" "$min_clock" || return 1
      validate_integer "${name}_max" "$max_clock" || return 1
      ;;
    *)
      validate_integer "$name" "$value" || return 1
      ;;
  esac
}

apply_values_to_gpu() {
  gpu="$1"
  power_limit_w="${2:-}"
  lock_core_clock_mhz="${3:-}"
  core_clock_offset_mhz="${4:-}"
  lock_memory_clock_mhz="${5:-}"
  memory_clock_offset_mhz="${6:-}"
  fan_speed_pct="${7:-}"
  delay_before_apply_s="${8:-}"

  if [ -n "$delay_before_apply_s" ] && validate_integer "delay_before_apply_s" "$delay_before_apply_s"; then
    if is_true "${KERYX_GPU_PRESETS_DRY_RUN:-false}"; then
      warn "DRY RUN: sleep ${delay_before_apply_s} before applying GPU ${gpu} preset"
    elif [ "$delay_before_apply_s" -gt 0 ]; then
      sleep "$delay_before_apply_s"
    fi
  fi

  run_setting "GPU ${gpu} persistence mode" nvidia-smi -i "$gpu" -pm 1

  if [ -n "$power_limit_w" ] && validate_integer "power_limit_w" "$power_limit_w"; then
    run_setting "GPU ${gpu} power limit ${power_limit_w}W" nvidia-smi -i "$gpu" -pl "$power_limit_w"
  fi

  if [ -n "$lock_core_clock_mhz" ] && validate_clock_value "lock_core_clock_mhz" "$lock_core_clock_mhz"; then
    run_setting "GPU ${gpu} locked core clock ${lock_core_clock_mhz}MHz" nvidia-smi -i "$gpu" -lgc "$(clock_range "$lock_core_clock_mhz")"
  fi

  if [ -n "$lock_memory_clock_mhz" ] && validate_clock_value "lock_memory_clock_mhz" "$lock_memory_clock_mhz"; then
    run_setting "GPU ${gpu} locked memory clock ${lock_memory_clock_mhz}MHz" nvidia-smi -i "$gpu" -lmc "$(clock_range "$lock_memory_clock_mhz")"
  fi

  if [ -n "$core_clock_offset_mhz" ] && validate_integer "core_clock_offset_mhz" "$core_clock_offset_mhz" true; then
    :
  else
    core_clock_offset_mhz=""
  fi

  if [ -n "$memory_clock_offset_mhz" ] && validate_integer "memory_clock_offset_mhz" "$memory_clock_offset_mhz" true; then
    :
  else
    memory_clock_offset_mhz=""
  fi

  if [ -n "$fan_speed_pct" ] && validate_integer "fan_speed_pct" "$fan_speed_pct"; then
    :
  else
    fan_speed_pct=""
  fi

  apply_nvidia_settings_offsets "$gpu" "$core_clock_offset_mhz" "$memory_clock_offset_mhz" "$fan_speed_pct"
}

apply_csv_presets() {
  resolved_preset_file=""
  fetch_preset_file || return 0
  preset_file="$resolved_preset_file"

  gpu_lines="$(nvidia-smi --query-gpu=index,name --format=csv,noheader 2>/dev/null || true)"
  if [ -z "$gpu_lines" ]; then
    fail_or_warn "no NVIDIA GPUs detected by nvidia-smi"
    return 0
  fi

  warn "applying GPU presets from ${preset_file}"
  printf '%s\n' "$gpu_lines" | while IFS=',' read -r gpu_index gpu_name || [ -n "${gpu_index:-}" ]; do
    gpu_index="$(trim "${gpu_index:-}")"
    gpu_name="$(trim "${gpu_name:-}")"
    [ -n "$gpu_index" ] && [ -n "$gpu_name" ] || continue

    preset_line="$(find_csv_preset_for_gpu "$preset_file" "$(lower "$gpu_name")" || true)"
    if [ -z "$preset_line" ]; then
      warn "no matching preset for GPU ${gpu_index}: ${gpu_name}"
      continue
    fi

    IFS=',' read -r enabled row_algorithm matcher power_limit_w lock_core_clock_mhz core_clock_offset_mhz lock_memory_clock_mhz memory_clock_offset_mhz fan_speed_pct delay_before_apply_s <<EOF
$preset_line
EOF

    warn "GPU ${gpu_index}: ${gpu_name} matched preset '$(trim "${matcher:-}")'"
    apply_values_to_gpu "$gpu_index" \
      "$(trim "${power_limit_w:-}")" \
      "$(trim "${lock_core_clock_mhz:-}")" \
      "$(trim "${core_clock_offset_mhz:-}")" \
      "$(trim "${lock_memory_clock_mhz:-}")" \
      "$(trim "${memory_clock_offset_mhz:-}")" \
      "$(trim "${fan_speed_pct:-}")" \
      "$(trim "${delay_before_apply_s:-}")"
  done
}

apply_env_tuning() {
  . /opt/keryx/gpu-presets.sh

  if is_true "${KERYX_GPU_RESET_CLOCKS_FIRST:-false}"; then
    for gpu in $(gpu_devices); do
      nvidia-smi -i "$gpu" -rgc >/dev/null 2>&1 || warn "failed to reset graphics clocks on GPU ${gpu}"
      nvidia-smi -i "$gpu" -rmc >/dev/null 2>&1 || warn "failed to reset memory clocks on GPU ${gpu}"
    done
  fi

  for gpu in $(gpu_devices); do
    power_limit_w=""
    if [ -n "${KERYX_GPU_POWER_LIMIT:-}" ]; then
      power_limit_w="$KERYX_GPU_POWER_LIMIT"
    elif [ -n "${KERYX_GPU_POWER_LIMIT_PERCENT:-}" ]; then
      power_limit_w="$(percent_power_limit "$gpu" "$KERYX_GPU_POWER_LIMIT_PERCENT")"
    fi

    apply_values_to_gpu "$gpu" \
      "$power_limit_w" \
      "${KERYX_GPU_LOCK_CORE_CLOCK:-}" \
      "${KERYX_GPU_CORE_CLOCK_OFFSET:-}" \
      "${KERYX_GPU_LOCK_MEMORY_CLOCK:-}" \
      "${KERYX_GPU_MEMORY_CLOCK_OFFSET:-}" \
      "" \
      ""
  done
}

if ! is_enabled; then
  exit 0
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  fail_or_warn "nvidia-smi is unavailable; GPU tuning skipped"
  exit 0
fi

if is_true "${KERYX_GPU_PRESETS_ENABLE:-false}" || [ -n "${KERYX_GPU_PRESETS_URL:-}" ]; then
  apply_csv_presets
else
  apply_env_tuning
fi
