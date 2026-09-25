# Stack identity, MPICH 8.1.32 vs LUMI 25.09

Recorded 2026-09-25 from the login-node link and from one-node
dev-g smokes. The comparison jobs reload these same module lines, and
each rank-0 log prints `MPI_Get_library_version`.

LUMI/24.03 can no longer load `cray-mpich` (the module exists only as
8.1.29, and `module load cray-mpich` is rejected). The 8.1.32 control
is the library the earlier reproducer linked, loaded from LUMI/25.03.

## Reference (arms A, B)

```bash
module --force purge
module load LUMI/25.03 partition/G
module load PrgEnv-cray
module load rocm/6.3.4
module load cray-mpich/8.1.32
export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_GPU_IPC_ENABLED=0
export FI_CXI_RX_MATCH_MODE=software
```

`MPICH_OFI_NIC_POLICY` is left unset.

| | |
|---|---|
| modules | LUMI/25.03, PrgEnv-cray/8.6.0, cce/19.0.0, craype/2.7.34, cray-mpich/8.1.32, rocm/6.3.4, libfabric/1.22.0 |
| compiler | `/opt/cray/pe/craype/2.7.34/bin/cc`, Cray clang 19.0.0 (`cc4d36e4`) |
| MPI, runtime | CRAY MPICH version 8.1.32.110 (ANL base 3.4a2), built Thu Feb 06 22:43 2025, git `f9c5634` |
| `libmpi` | `/opt/cray/pe/mpich/8.1.32/ofi/cray/17.0/lib/libmpi_cray.so.12.0.0` |
| header | `MPICH_VERSION "3.4a2"` under `CRAY_MPICH_DIR=.../ofi/crayclang/17.0` (that tree's `libmpi_cray.so` is a symlink to the path above) |
| ROCm | `/opt/rocm-6.3.4`, hipconfig `6.3.42134-a9a80e791` |
| libfabric | `/opt/cray/libfabric/1.22.0/lib64/libfabric.so.1.25.0` |
| libcxi | `/usr/lib64/libcxi.so.1.5.0` |
| smoke | job 22326814 (p2p) and 22326826 (`MPI_Alltoall`), both `PROBE OK` |

## LUMI 25.09 (arms C, D)

```bash
module --force purge
module load LUMI/25.09 partition/G
module load cpeAMD/25.09
module load lumi-CrayPath
export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_GPU_IPC_ENABLED=0
export MPICH_OFI_NIC_POLICY=GPU
export FI_CXI_RX_MATCH_MODE=software
```

| | |
|---|---|
| modules | LUMI/25.09, cpeAMD/25.09, lumi-CrayPath/0.1, PrgEnv-amd/8.6.0, craype/2.7.35, cray-mpich/9.0.1, rocm/6.4.4, amd/6.4.4, libfabric/1.22.0 |
| compiler | `/opt/cray/pe/craype/2.7.35/bin/cc`, AMD clang 19.0.0git roc-6.4.4 |
| MPI, runtime | CRAY MPICH version 9.0.1.498 (ANL base 4.1.2), built Wed Jul 16 9:29 2025, git `0848216` |
| `libmpi` | `/opt/cray/pe/mpich/9.0.1/ofi/amd/6.0/lib/libmpi_amd.so.12.0.0` |
| GTL | `/opt/cray/pe/mpich/9.0.1/ofi/amd/6.0/lib/libmpi_gtl_hsa.so.0` |
| header | `MPICH_VERSION "4.1.2"` |
| ROCm | `/appl/lumi/SW/LUMI-25.09/G/EB/rocm/6.4.4`, hipconfig `6.4.43484-123eb5128` |
| libfabric | `/opt/cray/libfabric/1.22.0/lib64/libfabric.so.1.25.0` (same file as the reference) |
| libcxi | `/usr/lib64/libcxi.so.1.5.0` (same file as the reference) |
| smoke | job 22326815 (p2p) and 22326827 (`MPI_Alltoall`), both `PROBE OK` |

The 25.09 binary does not resolve `libmpi_cray.so`. Under `cpeAMD` the
Cray MPICH 9.0.1 AMD build is `libmpi_amd.so.12`. `MPI_Get_library_version`
on the compute node is the check that this is not the 8.1.32 runtime.

libfabric and libcxi are the same files on both arms. A difference
between the arms is the MPI library, the ROCm version, the programming
environment, and `MPICH_OFI_NIC_POLICY=GPU` on 25.09 only.

Full `module list` and `ldd` output: `stack_ref.txt`, `stack_2509.txt`.
Per-job copies land in `runs/<jobid>-identity.txt`.
