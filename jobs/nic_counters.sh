#!/bin/bash
# Snapshot every Cassini telemetry counter on this node's NICs.
#   nic_counters.sh <outdir> <label>   writes <outdir>/<host>-<label>.txt
out="$1/$(hostname)-$2.txt"
for d in /sys/class/cxi/cxi*; do
  n=${d##*/}
  for f in "$d"/device/telemetry/*; do
    printf '%s %s %s\n' "$n" "${f##*/}" "$(cat "$f" 2>/dev/null)"
  done
  # Retry handler (cxi_rh) statistics, world-readable under /run/cxi.
  for f in /run/cxi/"$n"/*; do
    [[ -f "$f" ]] && printf '%s rh_%s %s\n' "$n" "${f##*/}" "$(cat "$f" 2>/dev/null)"
  done
done > "$out"
