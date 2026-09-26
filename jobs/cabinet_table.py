#!/usr/bin/env python3
"""Per A/B job: outcome, number of nodes in a cabinet, and that cabinet's
FGFC egress stall relative to the job median.
    jobs/cabinet_table.py [cabinet=x1304] [tag ...]"""
import glob, re, subprocess, statistics, collections, importlib.util, os, sys
here = os.path.dirname(os.path.abspath(__file__))
CAB = sys.argv[1] if len(sys.argv) > 1 else "x1304"
TAGS = sys.argv[2:] or ["ab2", "ab3"]
cab = dict(l.split() for l in open(os.path.join(here, "../evidence/provider/node-cabinet-map.txt")))
spec = importlib.util.spec_from_file_location("nd", os.path.join(here, "nic_delta.py"))
nd = importlib.util.module_from_spec(spec); spec.loader.exec_module(nd)
L = "/scratch/project_462001519/juaho/cray-cxi-bug/logs"
files = [f for t in TAGS for f in glob.glob(f"{L}/ab-{t}-*.out")]
for f in sorted(files, key=lambda p: p.rsplit("-", 1)[1]):
    t = open(f).read(); m = re.search(r"nodelist: (\S+)", t)
    if not m: continue
    nodes = subprocess.check_output(["scontrol", "show", "hostnames", m.group(1)],
                                    universal_newlines=True).split()
    n = sum(cab.get(x) == CAB for x in nodes)
    if "PROBE OK" in t: res = "OK"
    elif "PROBE CORRUPT" in t: res = "CORRUPT"
    elif "RESULT" in t: res = "FAIL"
    else: res = "run?"
    job = f.rsplit("-", 1)[1][:-4]; extra = ""
    try:
        snap = nd.load(job); per = collections.defaultdict(list)
        for (h, l) in list(snap):
            if l != "after" or (h, "before") not in snap: continue
            for c in ("cxi0", "cxi1", "cxi2", "cxi3"):
                a = snap[(h, "after")].get((c, "oxe_stall_fgfc_blk_0"))
                b = snap[(h, "before")].get((c, "oxe_stall_fgfc_blk_0"))
                if a is not None and b is not None: per[cab.get(h)].append(a - b)
        med = statistics.median([v for vs in per.values() for v in vs]) or 1
        if CAB in per:
            extra = (f"  {CAB} fgfc median {statistics.median(per[CAB])/med:.2f}x"
                     f" max {max(per[CAB])/med:.1f}x of job median")
    except Exception:
        extra = "  (no counters)"
    print(f"{os.path.basename(f)[:-4]:28s} {res:7s} {CAB}_nodes={n:2d}{extra}")
