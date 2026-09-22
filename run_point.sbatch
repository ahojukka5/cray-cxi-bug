#!/bin/bash
# One rank count, one matching mode. Separate jobs rather than steps,
# because a failed run hangs in srun teardown for about twenty minutes
# and would otherwise consume a whole sweep.
#
#   sbatch --nodes=64 --job-name=cxi-64n run_point.sbatch
#SBATCH --partition=standard-g
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-task=1
# --gpu-bind=closest resolves the "closest" GCD from the rank's CPU
# affinity. Without a CPU allocation per rank several ranks land in the
# same NUMA domain, are given the same GCD, and the device allocation
# below runs out of memory. That is a launch mistake and not the fault
# this reproduces, so these two are required, not decoration.
#SBATCH --cpus-per-task=7
#SBATCH --mem=0
#SBATCH --time=00:08:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
module load LUMI/24.03 partition/G 2>/dev/null || true
module load craype-accel-amd-gfx90a cray-mpich rocm 2>/dev/null || true

export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_GPU_IPC_ENABLED=0
export FI_CXI_RX_MATCH_MODE="${MATCH_MODE:-software}"
[[ -n "${RDZV_PROTO:-}" ]] && export FI_CXI_RDZV_PROTO="$RDZV_PROTO"
# fi_cxi(7) names these as the mitigation for resource exhaustion under
# many unmatched receives and unexpected messages, which is exactly this
# access pattern. Defaults are 12 MB and 3 posted for overflow, 12 MB
# and 6 posted for request buffers.
[[ -n "${OFLOW_SIZE:-}" ]] && export FI_CXI_OFLOW_BUF_SIZE="$OFLOW_SIZE"
[[ -n "${OFLOW_POSTED:-}" ]] && export FI_CXI_OFLOW_BUF_MIN_POSTED="$OFLOW_POSTED"
[[ -n "${REQ_SIZE:-}" ]] && export FI_CXI_REQ_BUF_SIZE="$REQ_SIZE"
[[ -n "${REQ_POSTED:-}" ]] && export FI_CXI_REQ_BUF_MIN_POSTED="$REQ_POSTED"

T=$SLURM_NTASKS
# Either follow production, where a fixed total volume makes the
# per-peer payload fall as 1/P^2, or hold the payload fixed to isolate
# rank count from message size. The latter is what small-node testing
# needs: at 64 ranks the production rule would demand 709 MB per peer.
if [[ -n "${FIXED_MB:-}" ]]; then MB="$FIXED_MB"
else MB=$(awk -v t="$T" 'BEGIN{printf "%.3f", 99.9e9*480/t/(16*(t-1))/1048576}'); fi
echo "nodes=$SLURM_JOB_NUM_NODES ranks=$T mode=${MATCH_MODE:-software} rdzv=${RDZV_PROTO:-default} payload=${MB}MB"

# BIN lets a variant binary be tested without overwriting the one
# that queued jobs will exec at run time.
srun --gpus-per-task=1 --gpu-bind=closest --cpu-bind=cores \
     "${BIN:-./alltoall_gpu}" --mb "$MB" --rounds "${ROUNDS:-40}" \
       ${WARM_ROUNDS:+--warm-rounds $WARM_ROUNDS} \
       ${WARM_BYTES:+--warm-bytes $WARM_BYTES} \
       ${STAGGER_MS:+--stagger-ms $STAGGER_MS} \
       ${HANDSHAKE:+--handshake} ${COLLECTIVE:+--collective} \
    && echo "RESULT ${T}r_${MATCH_MODE:-software}: OK" \
    || echo "RESULT ${T}r_${MATCH_MODE:-software}: FAILED"
