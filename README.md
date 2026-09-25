# Cray MPICH / CXI: device-buffer all-to-all fails above a rank threshold

A personalised all-to-all of multi-megabyte **GPU** buffers fails on
LUMI-G once the rank count passes a threshold between 480 and 512.
The failure is reproducible, is not a timeout, and happens with only
the HIP runtime allocator and MPI point-to-point calls in play.

We hit this in an exact-diagonalisation code and reduced it to the
~150-line C program here.

```
MPI_Waitall(count=1022, ...) failed
MPIR_Waitall(167)..............:
MPIR_Waitall_impl(51)..........:
MPID_Progress_wait(201)........:
MPIDI_Progress_test(97)........:
MPIDI_OFI_handle_cq_error(1310): OFI poll failed
  (ofi_events.c:1312:MPIDI_OFI_handle_cq_error:
   Input/output error - Invalid request descriptor)
```

A second signature, `No route to host`, appears from the same call site
at larger rank counts.

## Environment

| | |
|---|---|
| system | LUMI-G, SLES 15-SP6 |
| MPI | cray-mpich/8.1.32 |
| libfabric | 1.22.0 |
| network | craype-network-ofi, Slingshot 11, CXI provider |
| GPU | AMD MI250X, ROCm 6.3.4, craype-accel-amd-gfx90a |
| layout | 8 ranks per node, one GCD per rank, `--gpu-bind=closest` |

## What the program does

Each rank allocates two HIP device buffers holding one slot per peer,
then repeatedly:

1. posts `MPI_Irecv` from every peer into its slot of the receive
   buffer;
2. posts `MPI_Isend` to every peer from its slot of the send buffer;
3. calls `MPI_Waitall` on all `2(P-1)` requests.

There are no compute kernels. The only HIP calls are `hipSetDevice`,
`hipMalloc`, `hipMemset` and `hipDeviceSynchronize`. Buffers are
allocated once and reused every round, so nothing is registered or
freed inside the loop.

The per-peer payload defaults to what our application moves, a fixed
total volume divided among the ranks, so bytes per peer fall as `1/P²`:
about 12.4 MB at 480 ranks and 10.9 MB at 512.

## Reproducing

```bash
./build.sh
sbatch run_sweep.sbatch      # maps the threshold in one allocation
```

`run_sweep.sbatch` takes a node subset per arm at eight ranks per node,
so the rank count is the only variable, and sweeps both
`FI_CXI_RX_MATCH_MODE` settings. A single point is:

```bash
srun --nodes=64 --ntasks=512 --ntasks-per-node=8 \
     --gpus-per-task=1 --gpu-bind=closest \
     ./alltoall_gpu --mb 10.9 --rounds 40
```

## What we have observed

### There is no threshold

An earlier version of this file reported a clean threshold between 480
and 512 ranks. That was wrong, and the correction is instructive: the
same configuration gives different outcomes at different times of day,
so any single-sample comparison is unreliable. With repeats, neither
rank count nor message size predicts failure.

What does predict it is when the run happens.

### The same pattern in the application

Ten repeats per allocation, identical work, one frozen build:

| ranks | outcome |
|---:|---|
| 480 | 10/10 clean |
| 512 | failed, twice, both times in the first iteration |
| 768 | 10/10 clean |
| 1024 | 10/10 clean |
| 1536 | failed |
| 2048 | failed |

That 512 fails while 480, 768 and 1024 succeed is the part we cannot
explain. It rules out a simple monotonic resource ceiling.

### Things that do not fix it

Measured with all arms **submitted together**, six runs each, 60 nodes,
identical work, so every arm samples the same machine conditions:

| configuration | clean | failed |
|---|---:|---:|
| baseline, software matching | 3 | 3 |
| `FI_CXI_RDZV_PROTO=alt_read` | 1 | **5** |
| 32 MB overflow and request buffers | 3 | 3 |

No setting helps. `alt_read` is **worse**, and its failures are almost
all silent hangs rather than aborts.

Interleaving matters more than anything else here. Run in blocks
instead, the same three arms gave baseline 3 of 6 failing and
`alt_read` 0 of 5, which reads as a fix and is not one. The difference
was entirely *when* each block ran:

| window | clean | failed | rate |
|---|---:|---:|---:|
| 16:49 | 0 | 4 | 100% |
| 18:22 | 3 | 3 | 50% |
| 20:44 | 9 | 2 | 18% |
| 21:23 | 13 | 1 | 7% |
| 21:27 | 15 | 1 | 6% |

Identical work throughout. The rate fell from 100% to 6% over five
hours and later returned to 50%. Any comparison not interleaved in
time is measuring the machine, not the setting.

Also ruled out, each on interleaved or same-window evidence:

- **Message size.** 4, 8, 12 and 16 MB per peer at 480 ranks: one
  failure in sixteen runs, and it was at 4 MB. An earlier apparent
  threshold at 12 MB, matching the `FI_CXI_OFLOW_BUF_SIZE` default, was
  the same time confound.
- **Rank count.** 64 to 768 ranks at 4 MB: 15 runs, no failures.
- **Bounding requests in flight.** Restructuring to keep at most 64
  outstanding failed identically at `MPI_Waitall(count=64)`.
- **Completion queue size.** `FI_CXI_DEFAULT_CQ_SIZE=131072` and
  `FI_CXI_DEFAULT_TX_SIZE=4096` are set throughout; they removed an
  earlier, different error but not this one.

### Things that are not the cause

- **The application.** The C program here has none of it and fails the
  same way.
- **Bad nodes.** Across 20 allocations, 441 nodes appear in both failed
  and successful runs. Nodes appearing only in failures are explained
  by failed allocations simply being larger.
- **On-node GPU IPC.** A separate defect, where `hsa_amd_ipc_memory_attach`
  rejects views into a large allocation, is disabled throughout via
  `MPICH_GPU_IPC_ENABLED=0`.

### MPICH 9 and `MPI_Alltoall` do not do the same thing

Sixty nodes, 480 ranks, 12.431 MB per peer, 40 rounds. Six jobs per
arm, submitted in interleaved order and run between 12:08 and 13:25
on 2026-09-25. Account `project_462001120`. Full record:
`evidence/mpi9/results.md`.

| stack | exchange | jobs | clean | CXI fail | other | CXI rate | median time |
|---|---|---:|---:|---:|---:|---:|---:|
| MPICH 8.1.32.110 | point-to-point | 6 | 4 | 2 | 0 | 2/6 | 62.0 s |
| MPICH 8.1.32.110 | `MPI_Alltoall` | 6 | 6 | 0 | 0 | 0/6 | 39.2 s |
| MPICH 9.0.1.498 | point-to-point | 6 | 3 | 3 | 0 | 3/6 | 58.4 s |
| MPICH 9.0.1.498 | `MPI_Alltoall` | 6 | 5 | 0 | 1 | 0/6 | 35.5 s |

Every CXI failure is `Invalid request descriptor` from
`MPIDI_OFI_handle_cq_error`, then `Failed to destroy CXI Service ID`.
No `No route to host`, no hang. The one "other" is a GPU hang on
job 22337453, with no CXI line.

Point-to-point failed on both stacks (5 of 12). `MPI_Alltoall` did
not produce the CXI signature (0 of 12). Jobs that started in the
same wave still split by arm, so this is not one bad fabric window.
MPICH 9 did not help the point-to-point path: 3 of 6 failed, against
2 of 6 on 8.1.32. libfabric 1.22.0 and libcxi 1.5.0 are the same
files on both stacks.

`MPI_Alltoall` is also faster on the jobs that finish. That is a
separate fact. It does not carry the reliability claim.

## Our reading, offered tentatively

`Invalid request descriptor` names a rendezvous descriptor. Every
message here is far above `FI_CXI_RDZV_THRESHOLD`, observed as 16384
bytes, so all of them take the rendezvous path, and the pattern puts
every rank in simultaneous rendezvous with every other rank from device
memory. `FI_CXI_OFLOW_BUF_COUNT` is 3 by default.

We suspect exhaustion or mismanagement of rendezvous resources in the
CXI provider under this access pattern. We have not been able to
confirm it, and the non-monotonic threshold at 512 ranks argues that
something else is involved.

## Operational impact

Beyond the failure itself, a failed run leaves `srun` hanging in
teardown for roughly twenty minutes, so one failure consumes the whole
allocation. That turned a diagnosis loop into fifteen-minute samples
and is why the reduced reproducer here exists.

## Questions for HPE/Cray

1. Is this signature known for device-buffer all-to-all at these rank
   counts and message sizes?
2. Is there a supported setting that makes the rendezvous path safe
   here, or a recommended upper bound on concurrent large device
   rendezvous per rank?
3. Why would 512 ranks fail while 480, 768 and 1024 succeed with the
   same code, settings and payload scaling?
