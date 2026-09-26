#!/bin/bash
# One-node check of every arm: the LIBS line names the intended libfabric
# and --verify passes. Runs the arms as steps of one job.
#SBATCH --partition=dev-g
#SBATCH --account=project_462001519
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=7
#SBATCH --mem=0
#SBATCH --time=00:15:00
#SBATCH --output=/scratch/project_462001519/juaho/cray-cxi-bug/logs/%x-%j.out
#SBATCH --error=/scratch/project_462001519/juaho/cray-cxi-bug/logs/%x-%j.err
cd "${SLURM_SUBMIT_DIR}"
for a in ${ARMS:-sys shs12-ref shs12-diag}; do
  echo "################ $a"
  ARM=$a FIXED_MB=${FIXED_MB:-16} ROUNDS=${ROUNDS:-5} bash jobs/run_ab.sbatch
done
