#!/bin/bash
# Build the private libfabric trees and the reproducer on a compute node,
# and record the platform below MPI.
#SBATCH --partition=dev-g
#SBATCH --account=project_462001519
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --gpus=1
#SBATCH --time=00:45:00
#SBATCH --output=/scratch/project_462001519/juaho/cray-cxi-bug/logs/%x-%j.out
set -euo pipefail
cd "${SLURM_SUBMIT_DIR}"
LF=/scratch/project_462001519/juaho/cray-cxi-bug/lf
mkdir -p "$LF"
./record_platform.sh > "evidence/provider/platform-$(hostname).txt" 2>&1 || true
for t in ${TREES:-shs12-ref shs12-diag}; do
  echo "=== libfabric $t"
  ./libfabric/build_libfabric.sh "$HOME/dev/worktrees/libfabric/$t" "$LF/$t"
done
if [[ -z "${SKIP_BIN:-}" ]]; then
  module --force purge >/dev/null
  module load LUMI/25.03 partition/G
  module load PrgEnv-cray
  module load rocm/6.3.4
  module load cray-mpich/8.1.32
  mkdir -p bin
  cc -O2 -std=c11 -o bin/alltoall_gpu_ref alltoall_gpu.c \
     -I"${ROCM_PATH}/include" -L"${ROCM_PATH}/lib" -lamdhip64
  source ./record_stack.sh
  record_stack evidence/provider/stack_ref.txt bin/alltoall_gpu_ref
  sha256sum bin/alltoall_gpu_ref alltoall_gpu.c
fi
echo BUILD DONE
