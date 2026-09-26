#!/bin/bash
# One line per job of a provider A/B tag: arm, job, start, class, lib, and the
# first raw provider line that names a return code.
#   jobs/classify_ab.sh <tag>
cd "$(dirname "$0")/.."
L=/scratch/project_462001519/juaho/cray-cxi-bug/logs
TAG=${1:?tag}
printf '%-11s %-9s %-20s %-30s %-6s %s\n' arm job start class verify first_rc_line
grep -E '^[0-9]+ [^ ]+ [0-9]+$' "evidence/provider/$TAG/submit-order.txt" | while read -r _ arm job; do
  o="$L/ab-$TAG-$arm-$job.out"; e="$L/ab-$TAG-$arm-$job.err"
  if [[ ! -s "$o" ]]; then
    st=$(sacct -n -X -j "$job" -o State%12 | head -1 | xargs)
    printf '%-11s %-9s %-20s %s\n' "$arm" "$job" - "not-run:$st"; continue
  fi
  start=$(awk '/^start:/ {print substr($2,1,19)}' "$o")
  lib=$(grep -o 'libfabric=[^ ]*' "$o" | sed 's|.*/lf/||; s|/lib/.*||; s|libfabric=/opt.*|sys|')
  if grep -q 'PROBE OK' "$o"; then cls=clean
  elif grep -q 'PROBE CORRUPT' "$o"; then cls=CORRUPT
  elif grep -q -E 'Invalid request descriptor|Input/output error - CONN_CLOSED' "$e" 2>/dev/null; then cls=CONN_CLOSED
  elif grep -q 'No route to host' "$e" 2>/dev/null; then cls=no-route-to-host
  elif grep -q 'PMI_Init returned' "$e" 2>/dev/null; then cls=launch-failure-PMI
  elif grep -q 'GPU Hang' "$e" 2>/dev/null; then cls=gpu-hang
  elif grep -q 'RESULT.*FAILED rc=124' "$o"; then
    cls="harness-timeout@$(grep -o 'round *[0-9]*' "$o" | tail -1 | tr -s ' ' | tr ' ' '-')"
  elif grep -q 'DUE TO TIME LIMIT' "$e" 2>/dev/null; then cls=timeout/hang
  elif grep -q 'RESULT.*FAILED' "$o"; then cls=failed-other
  else cls=incomplete; fi
  v=$(grep -o 'VERIFY [A-Z]*' "$o" | tail -1 | cut -d' ' -f2)
  rcl=$(grep -h -m1 -E 'CXIDIAG .*REQ-ERROR|CXIDIAG .* EVENT type|cxi:.*(error|rc)' "$e" 2>/dev/null | cut -c1-160)
  # Arms named after a built tree must have loaded that tree.
  want=${arm%ex}; [[ -d "/scratch/project_462001519/juaho/cray-cxi-bug/lf/shs12-$want" ]] && want=shs12-$want
  [[ -d "/scratch/project_462001519/juaho/cray-cxi-bug/lf/$want" && "$lib" != "$want" ]] && cls="$cls LIB-MISMATCH($lib)"
  printf '%-11s %-9s %-20s %-30s %-6s %s\n' "$arm" "$job" "${start:--}" "$cls" "${v:--}" "$rcl"
done
