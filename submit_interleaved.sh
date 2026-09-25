#!/bin/bash
# Submit the four arms in an interleaved order so a fabric window
# does not land entirely on one arm.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p evidence/mpi9/logs evidence/mpi9/runs
order=(A B C D B D A C C A D B D C B A A B C D B D A C)
: > evidence/mpi9/submit-order.txt
echo "submitted: $(date -Is)" >> evidence/mpi9/submit-order.txt
for arm in "${order[@]}"; do
  id=$(sbatch --account=project_462001120 --job-name="cxi9-${arm}" --export=ALL,ARM="${arm}" run_arm.sbatch)
  echo "$arm $id" | tee -a evidence/mpi9/submit-order.txt
done
