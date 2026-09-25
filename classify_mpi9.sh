#!/bin/bash
# Classify the interleaved arm logs. Reads evidence/mpi9/logs and sacct.
set -euo pipefail
cd "$(dirname "$0")"
jobs=evidence/mpi9/submit-order.txt
out=evidence/mpi9/classification.tsv
echo -e "job\tarm\tstate\tclass\telapsed_s\texchange_s\tsignature" > "$out"
mkdir -p evidence/mpi9/signatures
while read -r arm rest; do
  [[ "$arm" =~ ^[ABCD]$ ]] || continue
  id=${rest##* }
  log="evidence/mpi9/logs/cxi9-${arm}-${id}.out"
  err="evidence/mpi9/logs/cxi9-${arm}-${id}.err"
  state=$(sacct -j "$id" -n -X --format=State | awk 'NR==1{print $1}')
  elapsed=$(sacct -j "$id" -n -X --format=ElapsedRaw | awk 'NR==1{print $1}')
  class=pending
  sig=""
  exch=""
  blob=""
  if [[ -f "$log" ]]; then blob=$(cat "$log"); fi
  if [[ -f "$err" ]]; then blob+=$'\n'"$(cat "$err")"; fi
  if echo "$blob" | grep -q "Invalid request descriptor"; then
    class=invalid_request
    sig="Invalid request descriptor"
  elif echo "$blob" | grep -q "No route to host"; then
    class=no_route
    sig="No route to host"
  elif echo "$blob" | grep -q "RESULT arm=${arm} .* OK"; then
    class=clean
    exch=$(echo "$blob" | awk '/PROBE OK/{print $(NF-1); exit}')
  elif echo "$blob" | grep -q "RESULT arm=${arm} .* FAILED"; then
    class=unrelated
    sig=$(echo "$blob" | awk '/MPICH ERROR|HIP_CHECK|error:/{print; exit}')
  elif [[ "$state" == "TIMEOUT" || "$state" == "CANCELLED" || "$state" == "NODE_FAIL" ]]; then
    class=hung
    sig="$state"
  elif [[ "$state" == "RUNNING" || "$state" == "PENDING" || -z "$state" ]]; then
    class="$state"
  elif [[ -n "$state" ]]; then
    class=unrelated
    sig="$state"
  fi
  if [[ "$class" == "invalid_request" || "$class" == "no_route" ]]; then
    sigfile="evidence/mpi9/signatures/${id}.txt"
    if [[ ! -f "$sigfile" ]]; then
      awk '
        /MPICH ERROR|Invalid request descriptor|No route to host|Failed to destroy CXI|switch_g_job_postfini|aborting job/ {p=1}
        p {print}
        p && NR>start+25 {exit}
        p && !start {start=NR}
      ' "$err" "$log" > "$sigfile" 2>/dev/null || true
    fi
  fi
  echo -e "${id}\t${arm}\t${state}\t${class}\t${elapsed}\t${exch}\t${sig}" >> "$out"
done < "$jobs"
column -t -s $'\t' "$out"
