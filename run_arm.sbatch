#!/bin/bash
# One arm of the MPICH-8 vs MPICH-9 × p2p vs MPI_Alltoall comparison.
# ARM=A  reference stack, point-to-point
# ARM=B  reference stack, MPI_Alltoall
# ARM=C  LUMI 25.09, point-to-point
# ARM=D  LUMI 25.09, MPI_Alltoall
#SBATCH --partition=standard-g
#SBATCH --account=project_462001120
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=7
#SBATCH --mem=0
#SBATCH --time=00:15:00
#SBATCH --nodes=60
#SBATCH --output=evidence/mpi9/logs/%x-%j.out
#SBATCH --error=evidence/mpi9/logs/%x-%j.err

set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
mkdir -p evidence/mpi9/logs evidence/mpi9/runs

case "${ARM:?ARM=A|B|C|D}" in
  A) STACK=ref;  COLLECTIVE="" ;;
  B) STACK=ref;  COLLECTIVE=1 ;;
  C) STACK=2509; COLLECTIVE="" ;;
  D) STACK=2509; COLLECTIVE=1 ;;
  *) echo "unknown ARM=$ARM"; exit 2 ;;
esac

module --force purge >/dev/null
if [[ "$STACK" == "ref" ]]; then
  module load LUMI/25.03 partition/G
  module load PrgEnv-cray
  module load rocm/6.3.4
  module load cray-mpich/8.1.32
else
  module load LUMI/25.09 partition/G
  module load cpeAMD/25.09
  module load lumi-CrayPath
fi

export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_GPU_IPC_ENABLED=0
export FI_CXI_RX_MATCH_MODE=software
if [[ "$STACK" == "2509" ]]; then
  export MPICH_OFI_NIC_POLICY=GPU
fi

BIN="bin/alltoall_gpu_${STACK}"
# shellcheck source=record_stack.sh
source ./record_stack.sh
record_stack "evidence/mpi9/runs/${SLURM_JOB_ID}-identity.txt" "$BIN"

T=$SLURM_NTASKS
if [[ -n "${FIXED_MB:-}" ]]; then MB="$FIXED_MB"
else MB=$(awk -v t="$T" 'BEGIN{printf "%.3f", 99.9e9*480/t/(16*(t-1))/1048576}'); fi
EXCH="p2p"
[[ -n "$COLLECTIVE" ]] && EXCH="alltoall"
echo "arm=$ARM stack=$STACK exchange=$EXCH nodes=$SLURM_JOB_NUM_NODES ranks=$T payload=${MB}MB rounds=${ROUNDS:-40}"
echo "start: $(date -Is)"

srun --gpus-per-task=1 --gpu-bind=closest --cpu-bind=cores \
     "$BIN" --mb "$MB" --rounds "${ROUNDS:-40}" \
       ${COLLECTIVE:+--collective} \
    && echo "RESULT arm=${ARM} stack=${STACK} exchange=${EXCH}: OK" \
    || echo "RESULT arm=${ARM} stack=${STACK} exchange=${EXCH}: FAILED"
echo "end: $(date -Is)"
