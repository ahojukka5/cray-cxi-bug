#!/bin/bash
# Snapshot every Cassini telemetry counter on this node's NICs.
#   nic_counters.sh <outdir> <label>   writes <outdir>/<host>-<label>.txt
out="$1/$(hostname)-$2.txt"
for d in /sys/class/cxi/cxi*; do
  n=${d##*/}
  for f in "$d"/device/telemetry/*; do
    printf '%s %s %s\n' "$n" "${f##*/}" "$(cat "$f" 2>/dev/null)"
  done
done > "$out"
