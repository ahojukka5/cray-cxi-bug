#!/bin/bash
# Build on LUMI-G. The Cray wrapper supplies MPI; HIP is linked
# directly because the program uses only the HIP runtime API and
# contains no device kernels, so no hipcc is needed.
set -euo pipefail
module load LUMI/24.03 partition/G 2>/dev/null || true
module load craype-accel-amd-gfx90a cray-mpich rocm 2>/dev/null || true
: "${ROCM_PATH:=/opt/rocm}"
cc -O2 -std=c11 -o alltoall_gpu alltoall_gpu.c \
   -I"${ROCM_PATH}/include" -L"${ROCM_PATH}/lib" -lamdhip64
echo "built alltoall_gpu against ${ROCM_PATH}"
