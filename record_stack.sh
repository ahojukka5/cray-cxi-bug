#!/bin/bash
# Append-free identity record. Sourced by the build and by each job.
record_stack() {
  local out="$1"
  local bin="${2:-}"
  {
    echo "timestamp: $(date -Is)"
    echo "hostname: $(hostname)"
    echo "slurm_job: ${SLURM_JOB_ID:-none}"
    echo "=== module list ==="
    module list 2>&1 || true
    echo "=== compiler wrapper ==="
    command -v cc || true
    cc --version 2>&1 || true
    echo "=== Cray MPICH ==="
    echo "CRAY_MPICH_DIR=${CRAY_MPICH_DIR:-unset}"
    if [[ -n "${CRAY_MPICH_DIR:-}" && -e "${CRAY_MPICH_DIR}/lib/libmpi_cray.so" ]]; then
      echo -n "libmpi_cray.so -> "
      readlink -f "${CRAY_MPICH_DIR}/lib/libmpi_cray.so"
    fi
    if [[ -n "${CRAY_MPICH_DIR:-}" ]]; then
      grep -R --include='*.h' -h -E 'define MPICH_VERSION |define MPICH_NUMVERSION ' \
        "${CRAY_MPICH_DIR}/include" 2>/dev/null | head -n 8 || true
    fi
    echo "=== ROCm ==="
    echo "ROCM_PATH=${ROCM_PATH:-unset}"
    if command -v hipconfig >/dev/null 2>&1; then
      hipconfig --version 2>&1 || true
    fi
    echo "=== libfabric / CXI ==="
    module show libfabric 2>&1 | awk 'NR==1 || /libfabric\//' || true
    echo "=== MPICH_* and FI_CXI_* ==="
    env | grep -E '^(MPICH_|FI_CXI_|FI_PROVIDER=)' | sort || true
    if [[ -n "$bin" && -e "$bin" ]]; then
      echo "=== ldd ${bin} ==="
      ldd "$bin" || true
      echo "=== resolved mpi / hip / fabric ==="
      ldd "$bin" | awk '/libmpi|libfabric|libcxi|libamdhip|libhsa/ {print}'
      local mpi_so
      mpi_so=$(ldd "$bin" | awk '/libmpi_.*\.so/ && !/gtl/ {print $3; exit}')
      if [[ -n "${mpi_so:-}" ]]; then
        echo "libmpi runtime -> $(readlink -f "$mpi_so")"
      fi
      local fab
      fab=$(ldd "$bin" | awk '/libfabric\.so/ {print $3; exit}')
      if [[ -n "${fab:-}" && -e "$fab" ]]; then
        echo "libfabric -> $(readlink -f "$fab")"
        echo "=== ldd $(readlink -f "$fab") (cxi) ==="
        ldd "$fab" | awk '/libcxi|libfabric/ {print}' || true
        local cxi
        cxi=$(ldd "$fab" | awk '/libcxi\.so/ {print $3; exit}')
        if [[ -n "${cxi:-}" && -e "$cxi" ]]; then
          echo "libcxi -> $(readlink -f "$cxi")"
        fi
      fi
    fi
  } > "$out"
}
