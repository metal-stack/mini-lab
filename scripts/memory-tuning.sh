#!/usr/bin/env bash
# Apply (and restore) host level memory tuning for the mini-lab.
#
# Both knobs are host-global, so the previous values are saved on "apply" and
# put back on "restore". Without the environment flags set this script is a
# no-op, which keeps the default behaviour of the lab unchanged.
#
#   MINI_LAB_KSM=true|false   enable kernel samepage merging (dedupes the
#                             identical guest RAM of leaf01/leaf02 and the
#                             machine VMs)
#   MINI_LAB_THP=madvise|always|never
#                             transparent hugepage policy; "madvise" stops the
#                             kernel from backing sparsely touched guest RAM
#                             with 2 MiB pages
#
# Usage: scripts/memory-tuning.sh apply|restore|show

set -euo pipefail

KSM_RUN=/sys/kernel/mm/ksm/run
KSM_SLEEP=/sys/kernel/mm/ksm/sleep_millisecs
KSM_PAGES=/sys/kernel/mm/ksm/pages_to_scan
THP_ENABLED=/sys/kernel/mm/transparent_hugepage/enabled
STATE_FILE="${MINI_LAB_MEMORY_TUNING_STATE:-.memory-tuning.state}"

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

write_sysfs() {
  local value=$1 path=$2
  if [ ! -w "$path" ] && [ -z "$SUDO" ]; then
    echo "memory-tuning: cannot write $path" >&2
    return 1
  fi
  if ! echo "$value" | $SUDO tee "$path" > /dev/null; then
    echo "memory-tuning: failed to write '$value' to $path." >&2
    echo "  KSM and THP are host global settings and need root. Either run with" >&2
    echo "  passwordless sudo, or unset MINI_LAB_KSM/MINI_LAB_THP to skip host tuning." >&2
    return 1
  fi
}

current_thp() {
  # "always [madvise] never" -> "madvise"
  sed -n 's/.*\[\(.*\)\].*/\1/p' "$THP_ENABLED" 2>/dev/null || echo ""
}

show() {
  echo "KSM run:        $(cat "$KSM_RUN" 2>/dev/null || echo 'n/a')"
  echo "KSM pages/scan: $(cat "$KSM_PAGES" 2>/dev/null || echo 'n/a')"
  echo "KSM saved:      $(( $(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 0) * 4 / 1024 )) MiB"
  echo "THP enabled:    $(current_thp)"
}

apply() {
  local ksm="${MINI_LAB_KSM:-}" thp="${MINI_LAB_THP:-}"

  if [ -z "$ksm" ] && [ -z "$thp" ]; then
    echo "memory-tuning: no flags set, nothing to do"
    return 0
  fi

  # only capture the pristine state the first time around, so repeated applies
  # (e.g. "make up" after "make partition") do not record our own values
  if [ ! -f "$STATE_FILE" ]; then
    {
      echo "KSM_RUN_ORIG=$(cat "$KSM_RUN" 2>/dev/null || echo '')"
      echo "THP_ORIG=$(current_thp)"
    } > "$STATE_FILE"
  fi

  if [ -n "$ksm" ]; then
    if [ ! -f "$KSM_RUN" ]; then
      echo "memory-tuning: KSM not available on this host (CONFIG_KSM missing)" >&2
    elif [ "$ksm" = "true" ]; then
      # a slightly more aggressive scan than the default so the lab converges
      # within the runtime of an integration test instead of hours
      write_sysfs "${MINI_LAB_KSM_PAGES_TO_SCAN:-1000}" "$KSM_PAGES" || true
      write_sysfs "${MINI_LAB_KSM_SLEEP_MS:-20}" "$KSM_SLEEP" || true
      write_sysfs 1 "$KSM_RUN"
      echo "memory-tuning: KSM enabled"
    else
      write_sysfs 0 "$KSM_RUN"
      echo "memory-tuning: KSM disabled"
    fi
  fi

  if [ -n "$thp" ]; then
    if [ ! -f "$THP_ENABLED" ]; then
      echo "memory-tuning: THP not available on this host" >&2
    else
      write_sysfs "$thp" "$THP_ENABLED"
      echo "memory-tuning: THP set to $thp"
    fi
  fi

  show
}

restore() {
  [ -f "$STATE_FILE" ] || { echo "memory-tuning: nothing to restore"; return 0; }

  # shellcheck disable=SC1090
  . "$STATE_FILE"

  if [ -n "${KSM_RUN_ORIG:-}" ] && [ -f "$KSM_RUN" ]; then
    if [ "$KSM_RUN_ORIG" = "0" ] && [ "$(cat "$KSM_RUN")" != "0" ]; then
      # 2 unmerges everything KSM merged and then stops scanning
      write_sysfs 2 "$KSM_RUN"
    else
      write_sysfs "$KSM_RUN_ORIG" "$KSM_RUN"
    fi
    echo "memory-tuning: KSM restored to $KSM_RUN_ORIG"
  fi

  if [ -n "${THP_ORIG:-}" ] && [ -f "$THP_ENABLED" ]; then
    write_sysfs "$THP_ORIG" "$THP_ENABLED"
    echo "memory-tuning: THP restored to $THP_ORIG"
  fi

  rm -f "$STATE_FILE"
}

case "${1:-}" in
  apply)   apply ;;
  restore) restore ;;
  show)    show ;;
  *)
    echo "usage: $0 apply|restore|show" >&2
    exit 1
    ;;
esac
