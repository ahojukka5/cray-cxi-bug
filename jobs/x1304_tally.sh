#!/bin/bash
# Point-to-point outcomes of the provider campaigns, stratified by whether the
# job had any node in a cabinet, joined on job id. Launch failures, harness
# timeouts and GPU hangs are listed but not counted as clean or failed.
#   jobs/x1304_tally.sh [cabinet] [tag ...]
cd "$(dirname "$0")/.."
CAB=${1:-x1304}; shift || true
TAGS=${*:-ab2 ab3 ab4 ab6}
join -1 1 -2 1 \
  <(for t in $TAGS; do jobs/classify_ab.sh "$t" | awk 'NR>1 {print $2, $1, $4}'; done | sort) \
  <(python3 jobs/cabinet_table.py "$CAB" $TAGS 2>/dev/null |
      sed -n 's/^ab-[^ ]*-\([0-9]*\) .*_nodes= *\([0-9]*\).*/\1 \2/p' | sort) |
awk -v cab="$CAB" '
  $3 ~ /^not-run|^incomplete/ {next}
  { where = ($4 > 0) ? "with" : "without"
    cls = ($3 == "CONN_CLOSED" || $3 == "clean") ? $3 : "other:" $3
    k[where " " cls]++; printf "%-9s %-11s %-26s %s=%s\n", $1, $2, $3, cab, $4 }
  END { print "---"; for (x in k) print x, k[x] }'
