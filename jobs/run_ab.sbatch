#!/bin/bash
# One arm of the provider A/B. The MPI stack, launch shape, payload and
# environment are identical across arms; only the libfabric that Cray MPICH
# loads differs, selected by LD_LIBRARY_PATH and proven by the LIBS line
# the binary prints from its own link map.
#   ARM=sys       /opt/cray/libfabric/1.22.0 (installed)
#   ARM=<tree>    $LF/<tree>/lib, e.g. shs12-ref, shs12-diag
#SBATCH --partition=standard-g
#SBATCH --account=project_462001519
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=7
#SBATCH --mem=0
#SBATCH --time=00:10:00
#SBATCH --nodes=60
#SBATCH --output=/scratch/project_462001519/juaho/cray-cxi-bug/logs/%x-%j.out
#SBATCH --error=/scratch/project_462001519/juaho/cray-cxi-bug/logs/%x-%j.err
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
LF=/scratch/project_462001519/juaho/cray-cxi-bug/lf
RUNS=/scratch/project_462001519/juaho/cray-cxi-bug/runs
mkdir -p "$RUNS"

module --force purge >/dev/null
module load LUMI/25.03 partition/G
module load PrgEnv-cray
module load rocm/6.3.4
module load cray-mpich/8.1.32

export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_GPU_IPC_ENABLED=0
export FI_CXI_RX_MATCH_MODE=software
# Warning-level provider logging in every arm: the CXI provider logs the
# return code of a failed request at WARN, and the level must not differ
# between arms.
export FI_LOG_LEVEL=warn
export FI_LOG_PROV=cxi

case "${ARM:?ARM=sys|<tree>}" in
  sys) ;;
  *) [[ -e "$LF/$ARM/lib/libfabric.so.1" ]] || { echo "no $LF/$ARM"; exit 2; }
     export LD_LIBRARY_PATH="$LF/$ARM/lib:${LD_LIBRARY_PATH:-}" ;;
esac

BIN=${BIN:-bin/alltoall_gpu_ref}
source ./record_stack.sh
record_stack "$RUNS/${SLURM_JOB_ID}-identity.txt" "$BIN"
[[ "$ARM" != sys ]] && cp "$LF/$ARM/BUILDINFO" "$RUNS/${SLURM_JOB_ID}-buildinfo.txt"

T=$SLURM_NTASKS
if [[ -n "${FIXED_MB:-}" ]]; then MB="$FIXED_MB"
else MB=$(awk -v t="$T" 'BEGIN{printf "%.3f", 99.9e9*480/t/(16*(t-1))/1048576}'); fi
echo "arm=$ARM nodes=$SLURM_JOB_NUM_NODES ranks=$T payload=${MB}MB rounds=${ROUNDS:-40} bin=$BIN"
echo "nodelist: $SLURM_JOB_NODELIST"
echo "start: $(date -Is)"
# Per-node NIC counters before and after the exchange. A failed run hangs in
# srun teardown for about twenty minutes, so the exchange is bounded by
# timeout and the second snapshot runs as an overlapping step.
CNT="$RUNS/${SLURM_JOB_ID}-nic"
mkdir -p "$CNT"
srun --ntasks-per-node=1 --ntasks="$SLURM_JOB_NUM_NODES" --gpus-per-task=0 \
     --cpus-per-task=1 jobs/nic_counters.sh "$CNT" before
echo "exchange start: $(date -Is)"
timeout -k 30 -s TERM "${EXCH_TIMEOUT:-330}" \
  srun --gpus-per-task=1 --gpu-bind=closest --cpu-bind=cores \
     "$BIN" --mb "$MB" --rounds "${ROUNDS:-40}" --verify \
  && echo "RESULT arm=$ARM: OK" || echo "RESULT arm=$ARM: FAILED rc=$?"
echo "exchange end: $(date -Is)"
srun --overlap --ntasks-per-node=1 --ntasks="$SLURM_JOB_NUM_NODES" \
     --gpus-per-task=0 --cpus-per-task=1 jobs/nic_counters.sh "$CNT" after
( cd "$RUNS" && tar czf "${SLURM_JOB_ID}-nic.tgz" "${SLURM_JOB_ID}-nic" && rm -rf "${SLURM_JOB_ID}-nic" )
echo "end: $(date -Is)"
