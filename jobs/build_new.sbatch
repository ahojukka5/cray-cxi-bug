#!/bin/bash
# Build json-c headers and the newer libfabric trees.
#SBATCH --partition=dev-g
#SBATCH --account=project_462001519
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --gpus=1
#SBATCH --time=01:00:00
#SBATCH --output=/scratch/project_462001519/juaho/cray-cxi-bug/logs/%x-%j.out
cd "${SLURM_SUBMIT_DIR}"
LF=/scratch/project_462001519/juaho/cray-cxi-bug/lf
[[ -e $LF/deps/json-c/include/json-c/json.h ]] || ./libfabric/build_jsonc.sh $LF/deps/json-c
for t in ${TREES:?TREES}; do
  echo "=== libfabric $t"
  ./libfabric/build_libfabric.sh "$HOME/dev/worktrees/libfabric/$t" "$LF/$t" \
     --with-json-c=$LF/deps/json-c --enable-cxi-json-dlopen --enable-cxi-curl-dlopen \
    && echo "BUILD OK $t" || echo "BUILD FAILED $t"
done
