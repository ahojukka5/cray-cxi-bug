# Below MPI: what `Invalid request descriptor` actually is

Campaign of 2026-09-26. 60 nodes, 480 ranks, 12.431 MB per peer, 40
rounds, point-to-point, `FI_CXI_RX_MATCH_MODE=software`, received data
verified every round (`--verify`). Cray MPICH 8.1.32, ROCm 6.3.4. Only the
libfabric that Cray MPICH loads changes between arms, and every run prints
the libfabric and libcxi it actually mapped (`LIBS ... same_on_all_ranks=yes`).

## Result in one paragraph

The MPI error is a Cassini NIC return code, `C_RC_CONN_CLOSED` (53), on the
**sender's** rendezvous source buffer, reported when the receiver's hardware
Get of that buffer finishes after the sender NIC has timed out the target
connection. In every failure the Get initiator, the MPI receiver, sits in
one cabinet, **x1304**, which is a single Slingshot group (fabric addresses
0xE800-0xEFFF, switches 928-959). That receiver NIC's traffic is held by
switch fine-grained flow control (FGFC) 11-84 times longer than the job
median. N of its packets each time out five times (1 + `max_spt_retries`)
in the retry handler, and after about 34 s (the TCT timeout, 2^35 cycles)
the peers' target connections close. libfabric reports the NIC status
faithfully. Four libfabric versions, from the installed one to upstream
`main`, fail the same way. The defect is below user space, in the fabric
path to or from cabinet x1304.

## How the message is produced

`MPIDI_OFI_handle_cq_error` prints `fi_strerror(err) - fi_strerror(prov_errno)`.
The CXI provider passes the raw Cassini return code as `prov_errno`, and
`fi_strerror` of a small number is `strerror`, so:

```text
err        = FI_EIO (5)            "Input/output error"   proverr2errno(53)
prov_errno = C_RC_CONN_CLOSED (53) "Invalid request descriptor" = strerror(53)
```

The English text is an accident of the errno table. It has nothing to do
with a request descriptor. `No route to host` from the same call site is
`C_RC_UNDELIVERABLE`, which `proverr2errno` maps to `FI_EHOSTUNREACH`.

Source path, installed revision `HewlettPackard/shs-libfabric@8dad011dfdb6`
(`release/shs-12.0.2`, the RPM `libfabric-1.22.0-SHS12.0.2_..._8dad011dfdb6`):

```text
C_EVENT_GET on the rendezvous source PtlTE, return_code 53
  prov/cxi/src/cxip_msg_hpc.c:4266  cxip_rdzv_pte_src_cb()
  prov/cxi/src/cxip_msg_hpc.c:4301    get_req->send.rc = event_rc
  prov/cxi/src/cxip_msg_hpc.c:4181  rdzv_send_req_event(): second event
  prov/cxi/src/cxip_msg_hpc.c:4159  rdzv_send_req_complete()
  prov/cxi/src/cxip_msg.c:669       proverr2errno(53) = FI_EIO
  prov/cxi/src/cxip_msg.c:677       cxip_cq_req_error(err=FI_EIO, prov_errno=53)
Cray MPICH ofi_events.c:1312       "OFI poll failed ... Input/output error - Invalid request descriptor"
```

## Captured event

With `FI_LOG_LEVEL=warn` the installed library already prints the code
(job 22358615):

```text
cxip_rdzv_pte_src_cb():4296 TXC (0xb951:0): Get error: 0x6454210 rc: CONN_CLOSED
cxip_report_send_completion():675 Request dest_addr: 432 caddr.nic: 0XEEC3 ... (err: 5, CONN_CLOSED)
```

The instrumented build (`libfabric/patches/0001-*.patch`) gives the raw
event and request (job 22358619, rank on nid007227):

```text
EVENT type=GET rc=53(CONN_CLOSED) buffer_id=2 ptlte=17 match_bits=0x82000000000033
      rlength=13032800 mlength=13032800
REQ   send len=13034848 tag=0x7 dest_addr=306 caddr.nic=0xef52 rdzv_id=563
      rc=53 rdzv_send_events=2 hmem_iface=2 (ROCR)
```

`mlength == rlength`: the sender NIC matched and served the whole Get. The
endpoint's event ring shows the previous event 50.26 s before this one;
nothing arrived in between. This is a timeout, not a bookkeeping race.

## Library equivalence and the newest libfabric (ab2, ab3)

| arm | source | CONN_CLOSED | clean | other |
|---|---|---:|---:|---:|
| sys (ab2) | installed `/opt/cray/libfabric/1.22.0` | 3 | 1 | 0 |
| shs12-ref (ab2) | self-built `8dad011dfdb6`, HPE configure line | 3 | 0 | 0 |
| shs12-diag (ab2) | same + diagnostics `1672ce9c4` | 2 | 0 | 1 GPU hang (nid007383) |
| sys (ab3) | installed | 2 | 5 | 1 GPU hang (nid007383) |
| shs15 (ab3) | HPE `release/shs-15.0` `9011331bb` (v2.7.0) | 3 | 5 | 0 |
| main (ab3) | upstream `ofiwg/libfabric@e1d76de13` (2.8.0a1) | 3 | 5 | 0 |

With libfabric 2.x the same Cray MPICH prints
`Input/output error - CONN_CLOSED` instead of `... - Invalid request
descriptor`: the newer provider names the Cassini code, which confirms the
decoding above. Every `CONN_CLOSED` in every arm had x1304 nodes (below).

ab2 was stopped after ten runs once the three builds had shown the same
failure; ab3 ran to completion. Per-job detail:
`ab2/classify.txt`, `ab3/classify.txt`. The GPU hang is a
node fault on nid007383, which also hung a GPU in job 22337453 on
2026-09-25.

## NIC and retry-handler counters

Every job snapshots all 1890 Cassini telemetry counters on every NIC, and
the `cxi_rh` statistics under `/run/cxi`, before and after the exchange
(`jobs/nic_counters.sh`, `jobs/nic_outliers.py`).

| job | libfabric | receiver NIC | FGFC stall / median | SPT timeouts | retries | error responses | senders with TCT timeout |
|---|---|---|---:|---:|---:|---:|---:|
| 22358615 | sys | nid007093/cxi0 | 23.5 | 320 | 256 | 64 | 1 |
| 22358618 | shs12-ref | nid007049/cxi3 | 23.3 | 205 | 164 | 41 | 5 |
| 22358619 | shs12-diag | nid007106/cxi1 | 84.0 | 320 | 256 | 64 | 6 |
| 22358621 | shs12-diag | nid007048/cxi3 | 11.1 | 520 | 416 | 104 | 3 |

N packets, five timeouts each (1 + `max_spt_retries=4` from
`/etc/cxi_rh.conf`), four retries each, then an error response each once the
target connection is gone. No other NIC in these jobs has an SPT timeout.
In 22358616 and 22358620 the receiver's node (nid006998, nid006995, both
x1304) hung in teardown and produced no second snapshot. Those nodes and
nid007048/049/100/106 were then drained by LUMI's health checks
(`switch_g_job_postfini failed`, ATOM timeouts).

The throttled NIC still sent 88-96 % of the median request volume, so it
was not blocked outright. Some of its flows were paused for very long: it
received 7-9 times the median number of FGFC frames. x1304 NIC edge links
show 3-5 times the median FEC-corrected codewords in all four jobs, with
no uncorrectable codewords and no link-level replays.

## Cabinet x1304

Receiver fabric addresses of all failing sends (`caddr.nic` of the
destination), 11 failures across four libfabric versions:

```text
0xEF52 0xEC32 0xE803 0xECB2 0xEB43 0xEEC3 0xE880 0xE882 0xEEE0 0xE9B3 0xEF22
```

All are in 0xE800-0xEFFF, switches 928-959, cabinet x1304
(nid006984-nid007107, 124 nodes, one of 24 LUMI-G cabinets). The senders are
spread over the machine.

Point-to-point jobs by whether any node was in x1304:

| | with x1304: CONN_CLOSED / clean | without: CONN_CLOSED / clean |
|---|---:|---:|
| this campaign, ab2-ab6, all libfabric builds (`x1304-tally.txt`) | 19 / 4 | 0 / 38 |
| mpi9, 2026-09-25, retrospective (`mpi9-retro-x1304.txt`) | 5 / 2 | 0 / 5 |

One-sided Fisher exact test: p = 3.0e-12 for this campaign, 5.0e-14 with
the retrospective jobs. Not counted: three GPU hangs, all on nid007383;
one PMI bootstrap failure; two healthy runs cut by the harness timeout
after a 180 s launch stall (ab4, 05:01); and one x1304-free run whose
first attempt died on a zero request-buffer header (below).

ab4 was the prospective test: installed libfabric, interleaved,
`--exclude=nid[006984-007107]` against unconstrained placement. ab6 added
twelve x1304-free runs of the instrumented build. All 38 valid x1304-free
runs completed 40 rounds with verified data.

`MPI_Alltoall` jobs with x1304 nodes: 0 / 6 failed (mpi9). The earliest
failures on 2026-09-21 (22197053, 22204152, 22209354, 22215040) all
included x1304 nodes. The two apparent exceptions that day (22214578,
22214579) were HIP out-of-memory launch errors.

This also explains the earlier finding that the failure rate tracked the
time of day and not any setting: what varied was whether the scheduler
placed the job on x1304.

Slurm already listed hardware faults in x1304 before this campaign:
nid007076 48 V fault, nid007041 NIC0 at PCIe Gen4 x8 instead of x16,
nid007038 GPU CECC errors (all 2026-09-25).

## Traffic that stays inside x1304

ab5 and ab7 placed all 60 nodes inside one cabinet (`--constraint=x1304`
or `x1305`), installed libfabric, same payload:

| placement | runs | CONN_CLOSED | clean, data verified | max FGFC stall / job median |
|---|---:|---:|---:|---:|
| all 60 nodes in x1304 (2026-09-26 13:16-14:20) | 8 | 0 | 8 | 1.3 |
| all 60 nodes in x1305 (2026-09-26 12:04-12:23) | 4 | 0 | 4 | - |

No NIC was throttled and no SPT timeout occurred. Every failure so far had
x1304 NICs exchanging with other cabinets, so the fault is on the path
between group 29 and the rest of the fabric, not inside the group.

Caveat: the last mixed-placement failure was at 06:56, six hours before
the first intra-x1304 run. The same-window control, eight x1304 nodes plus
52 in x1403 (`--constraint=[x1304*8&x1403*52]`, ab7), was never scheduled
before the 2026-09-27 full-machine reservation and was cancelled. The
inter-group reading is therefore the best-supported one, not a controlled
result.

## A second, rare signature

Job 22360089 (x1304 excluded, installed libfabric) aborted at round 1 on
nid005647 with `cxip_req_buf_get_header_info(): [Fatal] Unsupported fabric
header version: 0`: a Put into a software-matching request buffer whose
fabric header reads as zero. The node failed teardown and was drained;
Slurm requeued the job under the same id and overwrote the log, so the
lines are kept in `ab4/22360089-first-attempt.txt`. One occurrence in
about 60 runs. `cxip_req_buf_cb()` parses the header of every
`C_EVENT_PUT` without checking the event return code, in the installed
version and in upstream `main`. Whether the Put carried an error status
is not known; diagnostic `70baeb809` prints the event and header bytes if
it recurs (twelve ab6 runs did not reproduce it). All jobs now use
`--no-requeue`.

GPU hangs (`HW Exception ... GPU Hang`) occurred only on nid007383, four
times across campaigns including 22337453 on 2026-09-25. That node is
excluded from later jobs and is a separate hardware issue.

## Interpretation

Established: the failing layer is the Cassini reliability protocol (NIC
PCT plus the `cxi_rh` retry handler), fed by switch flow control that
holds one x1304 NIC's traffic past the retry budget. libfabric reports the
NIC status and is not the cause. No user-space fix is appropriate; turning
`CONN_CLOSED` into success on the sender would hide a Get whose delivery
the NIC could not confirm.

Not established: which element creates the congestion. Intra-x1304
traffic is clean, which favours the global links of group 29, or
congestion handling on them, over the group's own switches and NICs.
HPE and CSC can separate these with switch-side telemetry; the cabinet
power fault is the other candidate. `MPI_Alltoall` lowers the number of
concurrent flows and has so far not failed on x1304.

## Reproducing

```bash
sbatch jobs/build.sbatch            # libfabric trees + reproducer
jobs/submit_ab.sh <tag> 8 sys shs12-ref shs12-diag
jobs/classify_ab.sh <tag>
python3 jobs/nic_outliers.py <jobid>
python3 jobs/cabinet_table.py x1304 <tag>
```

Scratch: `/scratch/project_462001519/juaho/cray-cxi-bug/{logs,runs,lf}`.
Platform record: `platform-nid005002.txt`, `stack_ref.txt`.
