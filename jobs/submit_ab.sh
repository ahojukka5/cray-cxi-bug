#!/bin/bash
# Submit N rounds of the provider A/B, interleaved and rotated so that no arm
# systematically runs first. Appends job ids to evidence/provider/<tag>/submit-order.txt
#   jobs/submit_ab.sh <tag> <rounds> <arm> [<arm> ...]
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?tag}; N=${2:?rounds}; shift 2
ARMS=("$@")
OUT=evidence/provider/$TAG
mkdir -p "$OUT"
echo "submitted: $(date -Is) arms: ${ARMS[*]} rounds: $N" >> "$OUT/submit-order.txt"
k=${#ARMS[@]}
for ((r = 0; r < N; r++)); do
  for ((i = 0; i < k; i++)); do
    a=${ARMS[$(((i + r) % k))]}
    j=$(sbatch --parsable -J "ab-$TAG-$a" --export=ALL,ARM="$a" jobs/run_ab.sbatch)
    echo "$r $a $j" | tee -a "$OUT/submit-order.txt"
  done
done
