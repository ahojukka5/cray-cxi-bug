#!/bin/bash
# Build a private libfabric with the CXI provider against the system libcxi
# and CXI kernel headers, using the configure line HPE's own RPM build uses
# (contrib/cray/cray_rpmbuild.sh: --enable-only --enable-cxi
# --enable-restricted-dl, ROCr by dlopen) and the SLES system gcc 7.5 that
# built the installed library. CUDA and Level Zero are left out: LUMI has
# neither, and both are dlopen-only in the installed build. xpmem is off
# because the installed library does not link libxpmem.
#
#   build_libfabric.sh <source tree> <install prefix> [extra configure args]
#
# Run on a compute node. Writes <prefix>/BUILDINFO with the source commit,
# the dirty diff hash and the configure line.
set -euo pipefail
SRC=$(readlink -f "${1:?source tree}")
PREFIX="${2:?install prefix}"
shift 2
: "${ROCM_ROOT:=/opt/rocm-6.3.4}"
BUILD="${PREFIX}.build"
CONF=(--prefix="$PREFIX" --enable-only --enable-cxi --enable-restricted-dl
      --with-rocr="$ROCM_ROOT" --enable-rocr-dlopen --enable-xpmem=no "$@")

module --force purge >/dev/null 2>&1 || true
export CC=/usr/bin/gcc
cd "$SRC"
[[ -x configure ]] || ./autogen.sh >/dev/null
rm -rf "$BUILD" "$PREFIX"
mkdir -p "$BUILD"
cd "$BUILD"
"$SRC/configure" LDFLAGS=-Wl,--build-id "${CONF[@]}" > configure.log 2>&1 \
  || { tail -40 configure.log; exit 1; }
grep -E "^\*\*\*|cxi|rocr|kdreg2" configure.log | tail -20 || true
make -j"$(nproc)" > make.log 2>&1 || { grep -E "error|Error" make.log | head -40; exit 1; }
make install > install.log 2>&1
{
  echo "source: $SRC"
  echo "commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "describe: $(git -C "$SRC" describe --tags --always)"
  echo "dirty_diff_sha256: $(git -C "$SRC" diff HEAD | sha256sum | cut -d' ' -f1)"
  echo "untracked: $(git -C "$SRC" ls-files --others --exclude-standard prov/cxi | tr '\n' ' ')"
  echo "cc: $($CC --version | head -1)"
  echo "configure: LDFLAGS=-Wl,--build-id ${CONF[*]}"
  echo "host: $(hostname)  date: $(date -Is)  job: ${SLURM_JOB_ID:-none}"
  echo "libfabric.so: $(readlink -f "$PREFIX/lib/libfabric.so.1")"
  echo "sha256: $(sha256sum "$(readlink -f "$PREFIX/lib/libfabric.so.1")" | cut -d' ' -f1)"
  echo "ldd:"; ldd "$PREFIX/lib/libfabric.so.1" | sed 's/^/  /'
} > "$PREFIX/BUILDINFO"
cat "$PREFIX/BUILDINFO"
"$PREFIX/bin/fi_info" --version || true
