#!/bin/bash
# Build one named reproducer and record the stack it was linked against.
# STACK=ref  -> LUMI/25.03 + PrgEnv-cray + ROCm 6.3.4 + cray-mpich/8.1.32
#               (LUMI/24.03 can no longer load cray-mpich; this is the
#               8.1.32 crayclang library the earlier runs linked)
# STACK=2509 -> LUMI/25.09 + cpeAMD/25.09 + lumi-CrayPath (cray-mpich 9.0.1)
set -euo pipefail
cd "$(dirname "$0")"
STACK="${1:?STACK=ref or STACK=2509}"
case "$STACK" in
  ref|2509) ;;
  *) echo "unknown STACK=$STACK" >&2; exit 2 ;;
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

mkdir -p bin evidence/mpi9
BIN="bin/alltoall_gpu_${STACK}"
: "${ROCM_PATH:?ROCM_PATH unset after module load}"
cc -O2 -std=c11 -o "$BIN" alltoall_gpu.c \
   -I"${ROCM_PATH}/include" -L"${ROCM_PATH}/lib" -lamdhip64

# shellcheck source=record_stack.sh
source ./record_stack.sh
record_stack "evidence/mpi9/stack_${STACK}.txt" "$BIN"
echo "built $BIN"
tail -n 5 "evidence/mpi9/stack_${STACK}.txt"
