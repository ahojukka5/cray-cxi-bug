#!/bin/bash
# Build private libfabric trees on a CPU node. No GPU is needed: ROCr is
# only dlopened at run time.
#SBATCH --partition=small
#SBATCH --account=project_462001519
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=/scratch/project_462001519/juaho/cray-cxi-bug/logs/%x-%j.out
cd "${SLURM_SUBMIT_DIR}"
LF=/scratch/project_462001519/juaho/cray-cxi-bug/lf
for t in ${TREES:?TREES}; do
  echo "=== libfabric $t"
  ./libfabric/build_libfabric.sh "$HOME/dev/worktrees/libfabric/$t" "$LF/$t" \
    && echo "BUILD OK $t" || echo "BUILD FAILED $t"
done
