# LUMI-G: `CONN_CLOSED` on rendezvous Gets whose initiator is in cabinet x1304

For LUMI support (CSC) and HPE Slingshot. Prepared 2026-09-26.

## Summary

A bare-C MPI all-to-all of ROCm device buffers (480 ranks, 60 nodes,
12.4 MB per peer) aborts in `MPI_Waitall` when the job includes nodes of
cabinet **x1304** (nid006984-nid007107, fabric addresses 0xE800-0xEFFF,
switches 928-959). The NIC reports `C_RC_CONN_CLOSED` on the sender's
rendezvous source buffer after the receiver's hardware Get has been retried
past the target connection timeout. The receiver NIC in every case is in
x1304, and its traffic is held by switch fine-grained flow control (FGFC)
11-84 times longer than any other NIC in the job. Jobs without x1304 nodes
have not failed. User-space software (Cray MPICH 8.1.32 and 9.0.1; libfabric
from the installed SHS 12.0.2 build to upstream `main`) reports the NIC
status correctly and is not the cause.

## Stack

| | |
|---|---|
| OS | SLES 15 SP6, kernel 6.4.0-150600.23.73_15.0.14-cray_shasta_c |
| SHS | 12.0.2: cray-cxi-driver 1.0.0 (`27f7be52e4b1`), cray-libcxi 1.0.2 (`30fa2ddd65a2`), cxi_rh from the same RPM |
| NIC | Cassini, SS11 200Gb 2P P43012-002, firmware 1.5.59-ESM |
| libfabric | 1.22.0 = `HewlettPackard/shs-libfabric@8dad011dfdb6` (`release/shs-12.0.2`) |
| MPI | Cray MPICH 8.1.32.110 (`f9c5634`); also 9.0.1.498 |
| ROCm | 6.3.4 |
| cxi_rh config | `max_spt_retries=4`, `max_fabric_packet_age=0`, `max_sct_close_retries=0`; default epochs: SPT 2^30 (~1.07 s), TCT 2^35 (~34 s) |

Full records: `platform-nid005002.txt`, `stack_ref.txt`, per-job
`runs/<job>-identity.txt`.

## What the NIC reports

Sender side, CXI provider warning (job 22358615, installed libfabric):

```text
cxip_rdzv_pte_src_cb(): Get error: ... rc: CONN_CLOSED
cxip_report_send_completion(): Request dest_addr: 432 caddr.nic: 0XEEC3 ... (err: 5, CONN_CLOSED)
```

Raw event from an instrumented provider (job 22358619):

```text
C_EVENT_GET rc=53 (CONN_CLOSED) ptlte=17 buffer_id=2
  match_bits=0x82000000000033 rlength=13032800 mlength=13032800
request: tagged send 13034848 B from ROCm memory to rank 306 (caddr.nic 0xef52)
previous event on this EQ: 50.26 s earlier
```

Cray MPICH shows this as `Input/output error - Invalid request descriptor`
with the installed libfabric (`strerror(53)`), and as
`Input/output error - CONN_CLOSED` with libfabric 2.x.

## NIC and retry-handler counters around one failure

Telemetry deltas over the exchange, every NIC of the job
(`nic/<job>-outliers.txt`):

| job | receiver NIC | FGFC egress stall / job median | `pct_spt_timeouts` | `pct_retry_srb_requests` | `pct_rsp_err_rcvd` | `pct_bad_seq_nacks` | NICs with `pct_tct_timeouts` |
|---|---|---:|---:|---:|---:|---:|---:|
| 22358615 | nid007093/cxi0 | 23.5 | 320 | 256 | 64 | 1 | 1 |
| 22358618 | nid007049/cxi3 | 23.3 | 205 | 164 | 41 | 1 | 5 |
| 22358619 | nid007106/cxi1 | 84.0 | 320 | 256 | 64 | 1 | 6 |
| 22358621 | nid007048/cxi3 | 11.1 | 520 | 416 | 104 | 1 | 3 |

Reading: N packets from the receiver each time out 1 + `max_spt_retries`
times, then come back with an error response once the peer's TCT has
closed. No other NIC in these jobs records an SPT timeout. The throttled
NIC still issues 88-96 % of the median request count and receives 7-9 times
the median number of FGFC frames (`hni_fgfc_port`). Its link shows no
uncorrectable codewords and no LLR replays. x1304 NICs have 3-5 times the
median `hni_pcs_corrected_cw` in all four jobs.

After such a failure the receiver's node fails `switch_g_job_postfini`
(CXI service still busy, one SCT left in use) and is drained; this
happened to nid006995, nid006998, nid007048, nid007049, nid007100,
nid007106 on 2026-09-26.

## Placement statistics

Receiver fabric addresses of every failing send: 0xEF52 0xEC32 0xE803
0xECB2 0xEB43 0xEEC3 0xE880 0xE882 0xEEE0 0xE9B3 0xEF22, all in
0xE800-0xEFFF.

Point-to-point jobs, by whether any node was in x1304 (see
`README.md` for per-campaign tables):

| | CONN_CLOSED | clean, data verified |
|---|---:|---:|
| with x1304 nodes (2026-09-26) | 19 | 4 |
| without x1304 nodes (2026-09-26) | 0 | 38 |
| with x1304 nodes (2026-09-25, retrospective) | 5 | 2 |
| without x1304 nodes (2026-09-25, retrospective) | 0 | 5 |

One-sided Fisher exact p = 3.0e-12 (2026-09-26), 5.0e-14 pooled. Every
CXI failure recorded since 2026-09-21 had x1304 nodes. Four libfabric
builds were used (installed, self-built identical, v2.7.0, upstream main);
all fail the same way.

Jobs placed entirely inside x1304 (60 nodes, `--constraint=x1304`) were
clean 8 of 8 on 2026-09-26 13:16-14:20, with no throttled NIC, as were 4 of
4 inside x1305. Every failure had x1304 NICs exchanging with other
cabinets. A same-window mixed control could not be scheduled, so this
points at, but does not prove, the inter-group path of group 29.

Before this campaign Slurm listed in x1304: nid007076 48 V fault,
nid007041 NIC0 at PCIe Gen4 x8, nid007038 GPU CECC errors (2026-09-25).

## Suggested checks on the HPE/CSC side

1. Fabric manager / switch health for group 29 (switches 928-959): global
   link state and error counters, congestion-management (FGFC) statistics
   on the edge ports of the NICs above, around the job times listed.
2. The retry-handler journal (`cxi_rh@cxiN`) on the receiver nodes for the
   SPT timeouts and cancels at those times.
3. Whether the 48 V fault in x1304 affected switch or chassis power.

## Smallest reproducer

```bash
./build.sh                                 # or jobs/build.sbatch
sbatch -N 60 --constraint=x1304 ...        # all nodes in x1304
sbatch -N 60 --exclude=nid[006984-007107]  # control
srun --gpus-per-task=1 --gpu-bind=closest --cpu-bind=cores \
     ./alltoall_gpu --mb 12.431 --rounds 40 --verify
```

with `MPICH_GPU_SUPPORT_ENABLED=1 MPICH_GPU_IPC_ENABLED=0
FI_CXI_RX_MATCH_MODE=software FI_LOG_LEVEL=warn` (`jobs/run_ab.sbatch`).
A failure shows within the first two rounds as a 30-50 s stall followed by
the abort.
