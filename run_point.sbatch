#!/bin/bash
# One rank count, one matching mode. Separate jobs rather than steps,
# because a failed run hangs in srun teardown for about twenty minutes
# and would otherwise consume a whole sweep.
#
#   sbatch --nodes=64 --job-name=cxi-64n run_point.sbatch
#SBATCH --partition=standard-g
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-node=8
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

T=$SLURM_NTASKS
MB=$(awk -v t="$T" 'BEGIN{printf "%.3f", 99.9e9*480/t/(16*(t-1))/1048576}')
echo "nodes=$SLURM_JOB_NUM_NODES ranks=$T mode=${MATCH_MODE:-software} rdzv=${RDZV_PROTO:-default} payload=${MB}MB"

srun --gpus-per-task=1 --gpu-bind=closest --cpu-bind=cores \
     ./alltoall_gpu --mb "$MB" --rounds "${ROUNDS:-40}" \
    && echo "RESULT ${T}r_${MATCH_MODE:-software}: OK" \
    || echo "RESULT ${T}r_${MATCH_MODE:-software}: FAILED"
