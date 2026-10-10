# Scratch archive of the provider campaign

The unpacked scratch directory
`/scratch/project_462001519/juaho/cray-cxi-bug/{logs,runs,lf}` no longer
exists. On 2026-10-05 it was packed into one cold archive and removed:

```text
/scratch/project_462001519/juaho/cray-cxi-bug.tar.zst
sha256  4cc77dbe65ab2c2c01d172b82ad963f5757f79bf2605bcd9b6f6d730b3123169
size    937,870,420 bytes compressed, 1,690,111,209 bytes unpacked
entries 17,397 (16,508 files, 889 directories)
```

The sha256 was computed on 2026-10-10. The file and byte counts match the
line for this archive in
`/scratch/project_462001519/juaho/cold-archive/MANIFEST.tsv`. The
archive is the only copy of the members below that are not in git. Every
member has a 2026-09-26 timestamp.

## Members

| directory | files | bytes | content |
|---|---:|---:|---|
| `cray-cxi-bug/runs/` | 1,501 | 1,327,781,707 | per-job NIC telemetry and identity, 83 job IDs |
| `cray-cxi-bug/logs/` | 175 | 262,111,809 | Slurm `.out`/`.err` of ab2–ab7, builds, smoke, telem, rhstats |
| `cray-cxi-bug/lf/` | 14,832 | 100,217,693 | libfabric source and build trees |

`runs/` holds 1,310 raw Cassini counter files in `<job>-nic/<nid>-{before,after}.txt`,
70 `<job>-nic.tgz`, 83 `<job>-identity.txt` and 38 `<job>-buildinfo.txt`.
Git has 79 of the identity files, 34 of the buildinfo files and the reduced
counter tables under `evidence/provider/ab*/nic/`; the raw counter files
are only in the archive. `runs-index.tsv` lists every
job ID with its file counts and bytes.

`logs/` holds the full Slurm output of ab2–ab7 (158 files), five
`build.sbatch`, one each of `build_cpu.sbatch` and `build_new.sbatch`,
eight `smoke.sbatch`, `telem-22358599.out` and `rhstats-22359563.out`.
All 158 ab2–ab7 files are committed under `evidence/provider/ab*/logs/`.
The 79 `.out` files there have the same byte size as the archive
members. The 79 `.err` files are reduced: 146,500 bytes in git against
261,885,684 bytes in the archive. `logs-index.tsv` gives the archive size and
the committed size of every member.

`lf/` holds the trees `deps`, `main`, `shs12-diag`, `shs12-ref`, `shs13` and
`shs15`, each with its `.build` directory, as written by `jobs/build.sbatch`
through `libfabric/build_libfabric.sh`.

## Reading a member

```bash
tar -I zstd -xf /scratch/project_462001519/juaho/cray-cxi-bug.tar.zst \
    -C <empty-dir> cray-cxi-bug/runs/22360087-nic
```
