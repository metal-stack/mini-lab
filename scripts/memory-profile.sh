#!/usr/bin/env bash
# Print the environment for a named memory profile as KEY=value lines.
#
# The profiles are one-factor-at-a-time variations of "baseline" so that each
# knob can be compared on its own, plus "all" which combines them:
#
#   baseline     current defaults (4096 MB leaves, 2048 MB machines, no KSM,
#                THP=always) - the reference every other profile is diffed against
#   low-memory   reduced QEMU_MEMORY for leaves and machines
#   ksm          kernel samepage merging enabled on the host
#   thp-madvise  transparent hugepages restricted to madvise
#   all          everything above at once
#
# Usage:
#   scripts/memory-profile.sh low-memory            # KEY=value lines
#   eval "$(scripts/memory-profile.sh ksm --export)"
#   scripts/memory-profile.sh all >> "$GITHUB_ENV"

set -euo pipefail

profile="${1:-baseline}"
mode="${2:-}"

# defaults matching the committed topology defaults
leaf_memory=4096
machine_memory=2048
ksm=false
thp=always

case "$profile" in
  baseline)
    ;;
  low-memory)
    leaf_memory=2560
    machine_memory=1536
    ;;
  ksm)
    ksm=true
    ;;
  thp-madvise)
    thp=madvise
    ;;
  all)
    leaf_memory=2560
    machine_memory=1536
    ksm=true
    thp=madvise
    ;;
  *)
    echo "unknown memory profile: $profile" >&2
    echo "valid profiles: baseline low-memory ksm thp-madvise all" >&2
    exit 1
    ;;
esac

prefix=""
[ "$mode" = "--export" ] && prefix="export "

cat <<EOF
${prefix}MINI_LAB_MEMORY_PROFILE=${profile}
${prefix}MINI_LAB_LEAF_MEMORY=${leaf_memory}
${prefix}MINI_LAB_MACHINE_MEMORY=${machine_memory}
${prefix}MINI_LAB_KSM=${ksm}
${prefix}MINI_LAB_THP=${thp}
EOF
