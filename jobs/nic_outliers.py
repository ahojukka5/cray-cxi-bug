#!/usr/bin/env python3
"""NICs whose FGFC egress stall stands out, and every NIC with reliability
(PCT / retry handler) events, for one or more A/B jobs.
    jobs/nic_outliers.py <jobid> [...]"""
import sys, importlib.util, statistics
spec = importlib.util.spec_from_file_location("nd", __file__.replace("nic_outliers", "nic_delta"))
nd = importlib.util.module_from_spec(spec); spec.loader.exec_module(nd)
FLOW = ["oxe_stall_fgfc_blk_0", "hni_fgfc_port"]
REL = ["pct_spt_timeouts", "pct_tct_timeouts", "pct_retry_srb_requests",
       "pct_rsp_err_rcvd", "pct_bad_seq_nacks", "pct_tgt_cls_abort",
       "pct_sct_timeouts", "rh_spt_timeouts", "rh_tct_timeouts",
       "rh_pkts_cancelled_o", "rh_cancel_tct_closed", "rh_connections_cancelled"]
for job in sys.argv[1:]:
    snap = nd.load(job)
    rows, missing = {}, []
    for (h, l) in list(snap):
        if l != "before": continue
        if (h, "after") not in snap: missing.append(h); continue
        a, b = snap[(h, "after")], snap[(h, "before")]
        for n in ("cxi0", "cxi1", "cxi2", "cxi3"):
            rows[(h, n)] = {k: a.get((n, k), 0) - b.get((n, k), 0)
                            for k in FLOW + REL if (n, k) in a}
    med = statistics.median(r.get(FLOW[0], 0) for r in rows.values()) or 1
    print(f"job {job}: {len(rows)} NICs, no after-snapshot: {missing or 'none'}")
    top = sorted(rows.items(), key=lambda kv: -kv[1].get(FLOW[0], 0))[0]
    print(f"  max fgfc stall {top[0][0]}/{top[0][1]} x{top[1].get(FLOW[0],0)/med:.1f} "
          f"fgfc_frames={top[1].get('hni_fgfc_port')}")
    for k, r in sorted(rows.items()):
        ev = {x: r[x] for x in REL if r.get(x)}
        if ev:
            print(f"  rel {k[0]}/{k[1]} fgfc x{r.get(FLOW[0],0)/med:.1f} " +
                  " ".join(f"{x}={v}" for x, v in ev.items()))
