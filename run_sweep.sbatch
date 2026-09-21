#!/bin/bash
# Map the failure against rank count inside one allocation.
#
# Each arm takes a node subset at eight ranks per node, which is the
# production layout on LUMI-G, so the only variable is the rank count.
# A failing arm hangs in srun teardown for many minutes, so every step
# carries its own time limit.
#SBATCH --job-name=cxi-bug-sweep
#SBATCH --partition=standard-g
#SBATCH --nodes=192
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-task=1
# --gpu-bind=closest resolves the "closest" GCD from the rank's CPU
# affinity. Without a CPU allocation per rank several ranks land in the
# same NUMA domain, are given the same GCD, and the device allocation
# below runs out of memory. That is a launch mistake and not the fault
# this reproduces, so these two are required, not decoration.
#SBATCH --cpus-per-task=7
#SBATCH --mem=0
#SBATCH --time=00:50:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"

module load LUMI/24.03 partition/G 2>/dev/null || true
module load craype-accel-amd-gfx90a cray-mpich rocm 2>/dev/null || true

export MPICH_GPU_SUPPORT_ENABLED=1
# On-node HSA IPC rejects our buffers separately; disabled so that
# failure mode cannot be confused with this one.
export MPICH_GPU_IPC_ENABLED=0

ROUNDS="${ROUNDS:-40}"
ARM_MIN="${ARM_MIN:-4}"

arm() {
    local nodes="$1" mode="$2"
    local tasks=$((nodes * 8))
    # Payload as production sees it: a fixed total volume split over the
    # ranks, so bytes per peer fall as 1/P^2.
    local mb
    mb=$(awk -v t="$tasks" 'BEGIN{printf "%.3f", 99.9e9*480/t/(16*(t-1))/1048576}')
    echo "################ ${nodes} nodes / ${tasks} ranks / ${mode} / ${mb} MB ################"
    FI_CXI_RX_MATCH_MODE="$mode" \
    srun --nodes="$nodes" --ntasks="$tasks" --ntasks-per-node=8 \
         --gpus-per-task=1 --gpu-bind=closest --cpu-bind=cores \
         --time="$ARM_MIN" --kill-on-bad-exit=1 \
         ./alltoall_gpu --mb "$mb" --rounds "$ROUNDS" \
        && echo "ARM ${tasks}r_${mode}: OK" \
        || echo "ARM ${tasks}r_${mode}: FAILED"
}

for MODE in software hybrid; do
    for N in 60 62 64 68 80 96 128 192; do
        arm "$N" "$MODE"
    done
done

echo "################ summary ################"
grep -E "^ARM " "${SLURM_JOB_NAME}-${SLURM_JOB_ID}.out" || true
