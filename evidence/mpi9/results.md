# MPICH 8 vs MPICH 9, point-to-point vs MPI_Alltoall

60 nodes, 8 ranks per node, 480 ranks, one GCD per rank.
Payload 12.431 MB/peer, 40 rounds. Interleaved submission.
Window 2026-09-25 12:08–13:25. Account `project_462001120`.

`MPI_Alltoall` includes the self block that the point-to-point loop
skips: one peer out of 480, copied locally.

Stack identity is in `stacks.md`. Each rank-0 log prints
`MPI_Get_library_version`. Raw logs are
`evidence/mpi9/logs/cxi9-<arm>-<jobid>.out` and `.err`
(job 22337437 is `cxi9-prio-probe-22337437`).

| stack | exchange | nodes | jobs | clean | CXI fail | hung | other | CXI rate | median exchange time |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MPICH 8.1.32.110 | p2p | 60 | 6 | 4 | 2 | 0 | 0 | 2/6 | 62.0 s |
| MPICH 8.1.32.110 | MPI_Alltoall | 60 | 6 | 6 | 0 | 0 | 0 | 0/6 | 39.2 s |
| MPICH 9.0.1.498 | p2p | 60 | 6 | 3 | 3 | 0 | 0 | 3/6 | 58.4 s |
| MPICH 9.0.1.498 | MPI_Alltoall | 60 | 6 | 5 | 0 | 0 | 1 | 0/6 | 35.5 s |

Median time is over the clean jobs only, from `PROBE OK`.

## Jobs

| job | arm | start | class | exchange |
|---:|---|---|---|---:|
| 22337437 | A | 12:08:27 | Invalid request descriptor | |
| 22337449 | B | 12:18:07 | clean | 39.1 s |
| 22337451 | D | 12:39:06 | clean | 35.5 s |
| 22337452 | B | 12:39:06 | clean | 39.2 s |
| 22337453 | D | 12:39:06 | GPU hang | |
| 22337454 | A | 12:46:30 | clean | 62.1 s |
| 22337455 | C | 12:46:30 | Invalid request descriptor | |
| 22337456 | C | 12:46:30 | clean | 58.4 s |
| 22337457 | A | 12:50:56 | clean | 61.9 s |
| 22337458 | D | 12:50:56 | clean | 35.5 s |
| 22337459 | B | 12:50:56 | clean | 39.2 s |
| 22337460 | D | 12:58:14 | clean | 35.5 s |
| 22337461 | C | 12:58:14 | clean | 58.7 s |
| 22337462 | B | 13:06:04 | clean | 39.0 s |
| 22337463 | A | 13:06:04 | Invalid request descriptor | |
| 22337464 | A | 13:06:04 | clean | 62.1 s |
| 22337465 | B | 13:06:04 | clean | 39.3 s |
| 22337466 | C | 13:12:48 | clean | 57.2 s |
| 22337467 | D | 13:12:48 | clean | 35.5 s |
| 22337468 | B | 13:12:48 | clean | 39.2 s |
| 22337469 | D | 13:12:48 | clean | 35.6 s |
| 22337470 | A | 13:23:04 | clean | 61.9 s |
| 22337471 | C | 13:23:04 | Invalid request descriptor | |
| 22337450 | C | 13:23:04 | Invalid request descriptor | |

Arms that started together did not share an outcome. At 12:39 one
MPICH 9 `MPI_Alltoall` hung the GPU while another MPICH 9
`MPI_Alltoall` and an MPICH 8 `MPI_Alltoall` completed. At 12:46 and
at 13:23 a MPICH 9 point-to-point job aborted beside a clean job of
another arm.
At 13:06 an MPICH 8 point-to-point job aborted beside a clean run of
the same arm.

## CXI signature

MPICH 8.1.32, `PMPI_Waitall`, `ofi_events.c:1312`:

```text
MPICH ERROR [Rank 202] [job id 22337437.0] [Fri Sep 25 12:09:31 2026] [nid005874]
Fatal error in PMPI_Waitall: Other MPI error
MPIDI_OFI_handle_cq_error(1310): OFI poll failed
  (ofi_events.c:1312:MPIDI_OFI_handle_cq_error:
   Input/output error - Invalid request descriptor)
error: Failed to destroy CXI Service ID 5 (cxi2): Device or resource busy
error: switch_g_job_postfini: Device or resource busy
```

The same stack on 22337463, rank 441, nid007232, 13:07:12, cxi3.

MPICH 9.0.1, `internal_Waitall`, `ofi_events.c:981`. Same descriptor
text. Jobs 22337455 (rank 122), 22337450 (rank 256), 22337471
(rank 280).

## The other failure

Job 22337453, MPICH 9 `MPI_Alltoall`, nid007383:

```text
HW Exception by GPU node-4 (Agent handle: 0x2d1f90) reason :GPU Hang
srun: error: nid007383: tasks 425-431: Aborted
```

No `Invalid request descriptor` line.

## Reading

`MPI_Alltoall` is the arm that separates. It did so on both MPI
stacks. MPICH 9 did not reduce the point-to-point failure rate.
The provider libraries did not change, so this is the collective
implementation, not a newer libfabric.

The collective is also faster when it finishes. Reliability is the
failure column, not the times.
