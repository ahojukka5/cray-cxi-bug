#!/bin/bash
# One line per job of a provider A/B tag: arm, job, start, class, lib, and the
# first raw provider line that names a return code.
#   jobs/classify_ab.sh <tag>
cd "$(dirname "$0")/.."
L=/scratch/project_462001519/juaho/cray-cxi-bug/logs
TAG=${1:?tag}
printf '%-11s %-9s %-20s %-30s %-6s %s\n' arm job start class verify first_rc_line
grep -v '^submitted' "evidence/provider/$TAG/submit-order.txt" | while read -r _ arm job; do
  o="$L/ab-$TAG-$arm-$job.out"; e="$L/ab-$TAG-$arm-$job.err"
  if [[ ! -s "$o" ]]; then
    st=$(sacct -n -X -j "$job" -o State%12 | head -1 | xargs)
    printf '%-11s %-9s %-20s %s\n' "$arm" "$job" - "not-run:$st"; continue
  fi
  start=$(awk '/^start:/ {print substr($2,1,19)}' "$o")
  lib=$(grep -o 'libfabric=[^ ]*' "$o" | sed 's|.*/lf/||; s|/lib/.*||; s|libfabric=/opt.*|sys|')
  if grep -q 'PROBE OK' "$o"; then cls=clean
  elif grep -q 'PROBE CORRUPT' "$o"; then cls=CORRUPT
  elif grep -q 'Invalid request descriptor' "$e" 2>/dev/null; then cls=invalid-request-descriptor
  elif grep -q 'No route to host' "$e" 2>/dev/null; then cls=no-route-to-host
  elif grep -q 'DUE TO TIME LIMIT' "$e" 2>/dev/null; then cls=timeout/hang
  elif grep -q 'RESULT.*FAILED' "$o"; then cls=failed-other
  else cls=incomplete; fi
  v=$(grep -o 'VERIFY [A-Z]*' "$o" | tail -1 | cut -d' ' -f2)
  rcl=$(grep -h -m1 -E 'CXIDIAG .*REQ-ERROR|CXIDIAG .* EVENT type|cxi:.*(error|rc)' "$e" 2>/dev/null | cut -c1-160)
  [[ "$lib" != "$arm" && "$arm" != sys ]] && cls="$cls LIB-MISMATCH($lib)"
  printf '%-11s %-9s %-20s %-30s %-6s %s\n' "$arm" "$job" "${start:--}" "$cls" "${v:--}" "$rcl"
done
