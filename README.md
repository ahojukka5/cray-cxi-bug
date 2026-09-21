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

### The threshold

Measured with a Julia MPI + ROCArray program using the identical
communication pattern to `alltoall_gpu.c`: same all-to-all of device
buffers, no compute kernels. The C program here is the further-reduced
equivalent for handover. It is verified to build on LUMI-G; its own
runs at these rank counts are queued and this table will be updated
with them.

| ranks | nodes | payload | `FI_CXI_RX_MATCH_MODE=software` |
|---:|---:|---:|---|
| 480 | 60 | 12.43 MB | OK, all rounds |
| 512 | 64 | 10.92 MB | **FAILED**, on the first `MPI_Waitall` |

Larger rank counts and the `hybrid` mode are still being swept; this
README will be updated with the full table.

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

- **`FI_CXI_RX_MATCH_MODE=software`.** Adopted after it appeared to fix
  1024 ranks. It does not: 512 ranks then failed twice, having
  previously run 229 consecutive iterations under `hybrid`.
- **Bounding requests in flight.** Restructuring the exchange to keep
  at most 64 requests outstanding, instead of `2(P-1)`, failed with the
  identical error at `MPI_Waitall(count=64)`. The number of concurrent
  requests is not the trigger.
- **Larger completion queues.** `FI_CXI_DEFAULT_CQ_SIZE=131072` and
  `FI_CXI_DEFAULT_TX_SIZE=4096` are set in all runs above; they removed
  an earlier, different error but not this one.
- **Request buffer size and count.** `FI_CXI_REQ_BUF_MIN_POSTED=8` and
  `FI_CXI_REQ_BUF_SIZE=8388608` made no reproducible difference.

### Things that are not the cause

- **The application.** The C program here has none of it and fails the
  same way.
- **Bad nodes.** Across 20 allocations, 441 nodes appear in both failed
  and successful runs. Nodes appearing only in failures are explained
  by failed allocations simply being larger.
- **On-node GPU IPC.** A separate defect, where `hsa_amd_ipc_memory_attach`
  rejects views into a large allocation, is disabled throughout via
  `MPICH_GPU_IPC_ENABLED=0`.

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
