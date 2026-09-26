#!/usr/bin/env python3
"""Per-NIC telemetry deltas (after - before) for one A/B job.

    jobs/nic_delta.py <jobid> [--all] [--node NID]

Prints, for counters whose names suggest errors, retries, NACKs, timeouts or
drops, the job-wide sum, the number of NICs with a non-zero delta and the top
NICs. --all prints every counter that moved.
"""
import re, sys, tarfile, collections

RUNS = "/scratch/project_462001519/juaho/cray-cxi-bug/runs"
ERRISH = re.compile(r"(err|nack|timeout|retry|retries|drop|cls|abort|cancel|"
                    r"undeliver|discard|fail|poison|unsuccess|seq|busy|"
                    r"no_tct|no_trs|no_mst|restart|spt|sct|tct|trs|mst_)", re.I)

def members(jobid):
    """(name, text) for each snapshot, from the tarball or, when the job hit
    its time limit before archiving, from the directory."""
    import os
    d = f"{RUNS}/{jobid}-nic"
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            yield f, open(os.path.join(d, f)).read()
        return
    with tarfile.open(f"{d}.tgz") as t:
        for m in t.getmembers():
            if m.isfile():
                yield m.name.rsplit("/", 1)[1], t.extractfile(m).read().decode()

def load(jobid):
    snap = collections.defaultdict(dict)   # (host, label) -> {(nic, ctr): val}
    if True:
        for name, text in members(jobid):
            host, label = name[:-4].rsplit("-", 1)
            for line in text.splitlines():
                p = line.split(" ", 2)
                if len(p) < 3:
                    continue
                v = p[2].split("@", 1)[0]
                try:
                    snap[(host, label)][(p[0], p[1])] = int(v)
                except ValueError:
                    pass
    return snap

def main():
    jobid = sys.argv[1]
    show_all = "--all" in sys.argv
    node = sys.argv[sys.argv.index("--node") + 1] if "--node" in sys.argv else None
    snap = load(jobid)
    hosts = sorted({h for h, _ in snap})
    delta = collections.defaultdict(dict)  # ctr -> {(host, nic): d}
    missing = []
    for h in hosts:
        b, a = snap.get((h, "before")), snap.get((h, "after"))
        if not b or not a:
            missing.append(h)
            continue
        for k, va in a.items():
            d = va - b.get(k, va)
            if d:
                delta[k[1]][(h, k[0])] = d
    print(f"job {jobid}: {len(hosts)} nodes, missing snapshot: {missing or 'none'}")
    for ctr in sorted(delta):
        if not show_all and not ERRISH.search(ctr):
            continue
        per = delta[ctr]
        if node:
            per = {k: v for k, v in per.items() if k[0] == node}
            if not per:
                continue
        top = sorted(per.items(), key=lambda kv: -abs(kv[1]))[:4]
        print(f"{ctr:48s} sum={sum(per.values()):>12d} nics={len(per):>4d}  " +
              " ".join(f"{h}/{n}={v}" for (h, n), v in top))

if __name__ == "__main__":
    main()
