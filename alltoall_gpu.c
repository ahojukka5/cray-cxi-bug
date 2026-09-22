/* Minimal reproducer: Cray MPICH / CXI fails a device-buffer all-to-all
 * above a rank-count threshold on LUMI-G.
 *
 * Every rank posts one MPI_Irecv from every peer and one MPI_Isend to
 * every peer, all from HIP device memory, then waits on all of them.
 * That is a plain personalised all-to-all expressed with point-to-point
 * calls. There are no compute kernels: the only HIP calls are
 * hipSetDevice, hipMalloc and hipMemset, so nothing here can corrupt
 * state or race.
 *
 * At 480 ranks it runs indefinitely. At 512 ranks it fails, usually on
 * the very first MPI_Waitall, with
 *
 *   MPIDI_OFI_handle_cq_error(1310): OFI poll failed
 *     (Input/output error - Invalid request descriptor)
 *
 * Build:  see build.sh
 * Run:    see run_sweep.sbatch
 */

/* nanosleep needs the POSIX realtime declarations. */
#define _POSIX_C_SOURCE 199309L

#include <mpi.h>
#include <hip/hip_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define HIP_CHECK(x)                                                        \
    do {                                                                    \
        hipError_t e_ = (x);                                                \
        if (e_ != hipSuccess) {                                             \
            fprintf(stderr, "HIP error %s at %s:%d\n",                      \
                    hipGetErrorString(e_), __FILE__, __LINE__);             \
            MPI_Abort(MPI_COMM_WORLD, 1);                                   \
        }                                                                   \
    } while (0)

int main(int argc, char **argv)
{
    /* Bytes each rank sends to each peer, and how many all-to-alls to
     * run. Defaults match the production payload at 512 ranks. */
    size_t bytes_per_peer = 10ul * 1024 * 1024;
    int rounds = 50;
    /* Exchange the same bytes through MPI_Alltoall instead of the
     * hand-rolled post-all/wait loop. The per-peer strips are already
     * contiguous and equal sized, so the two move identical volume and
     * differ only in who schedules it: us, or Cray's collective. */
    int collective = 0;
    int report_every = 10;
    /* Optional warm-up: this many all-to-alls of `warm_bytes` before
     * the real payload. Every failure observed so far happens in the
     * first one or two exchanges and none later, which points at
     * per-peer state being established on first use. A warm-up below
     * FI_CXI_RDZV_THRESHOLD (16384 by default) establishes that state
     * on the eager path, without asking for rendezvous resources. */
    int warm_rounds = 0;
    size_t warm_bytes = 1024;
    /* Optional stagger: each rank waits a random interval up to this
     * many milliseconds before its first exchange. The warm-up above
     * lowers the message size but still fires every peer pair at the
     * same instant; this lowers the instantaneous concurrency instead,
     * which is the other way the provider could be running out of
     * per-peer resources. */
    int stagger_ms = 0;
    /* Graduated pairwise handshake. Walks the message size from small
     * to the production maximum, timing every ordered pair, then
     * finishes with one full-size all-to-all. It warms every peer pair
     * gradually instead of firing them all at full size at once, and
     * it yields a bandwidth map of the allocation as a side effect. */
    int handshake = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--mb") && i + 1 < argc)
            bytes_per_peer = (size_t)(atof(argv[++i]) * 1024 * 1024);
        else if (!strcmp(argv[i], "--rounds") && i + 1 < argc)
            rounds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--collective"))
            collective = 1;
        else if (!strcmp(argv[i], "--report") && i + 1 < argc)
            report_every = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--warm-rounds") && i + 1 < argc)
            warm_rounds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--warm-bytes") && i + 1 < argc)
            warm_bytes = (size_t)atol(argv[++i]);
        else if (!strcmp(argv[i], "--stagger-ms") && i + 1 < argc)
            stagger_ms = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--handshake"))
            handshake = 1;
        else {
            fprintf(stderr, "usage: %s [--mb F] [--rounds N] [--report N]\n",
                    argv[0]);
            return 2;
        }
    }

    int provided = 0;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_MULTIPLE, &provided);
    int world, me;
    MPI_Comm_size(MPI_COMM_WORLD, &world);
    MPI_Comm_rank(MPI_COMM_WORLD, &me);

    /* With --gpu-bind=closest each rank is given exactly one GCD, so
     * device 0 is this rank's GCD. Fall back to the local rank id. */
    int ndev = 0;
    HIP_CHECK(hipGetDeviceCount(&ndev));
    const char *local = getenv("SLURM_LOCALID");
    int dev = (ndev > 1 && local) ? (atoi(local) % ndev) : 0;
    HIP_CHECK(hipSetDevice(dev));

    /* Report the binding and the free memory before allocating. If
     * several ranks land on one GCD, which happens when the job asks
     * for GPUs per node instead of per task, the allocation below runs
     * out of memory and that is a launch mistake, not the fault this
     * program is for. */
    size_t hfree = 0, htotal = 0;
    HIP_CHECK(hipMemGetInfo(&hfree, &htotal));

    /* One contiguous send region and one receive region, each holding a
     * slot per peer. The production code sends views of a large tile,
     * which this mirrors: the buffers are big and the per-peer pieces
     * are offsets into them, not separate allocations. */
    size_t total = bytes_per_peer * (size_t)world;
    if (me == 0) {
        printf("ranks=%d  payload=%.3f MB/peer  device buffers=%.2f GiB/rank"
               "  rounds=%d  thread_level=%d  exchange=%s\n",
               world, (double)bytes_per_peer / (1024 * 1024),
               2.0 * (double)total / (1024.0 * 1024 * 1024), rounds, provided,
               collective ? "MPI_Alltoall" : "p2p");
        fflush(stdout);
        printf("  visible GCDs per rank=%d  using device %d"
               "  free=%.1f GiB of %.1f GiB\n",
               ndev, dev, (double)hfree / (1024.0 * 1024 * 1024),
               (double)htotal / (1024.0 * 1024 * 1024));
        static const char *vars[] = {
            "MPICH_GPU_SUPPORT_ENABLED", "MPICH_GPU_IPC_ENABLED",
            "FI_CXI_RX_MATCH_MODE", "FI_CXI_RDZV_PROTO",
            "FI_CXI_RDZV_THRESHOLD", "FI_CXI_DEFAULT_CQ_SIZE",
            "FI_CXI_DEFAULT_TX_SIZE", "FI_CXI_REQ_BUF_MIN_POSTED",
            "FI_CXI_REQ_BUF_SIZE", "FI_CXI_OFLOW_BUF_COUNT", NULL };
        for (int i = 0; vars[i]; i++) {
            const char *v = getenv(vars[i]);
            if (v) printf("  %s=%s\n", vars[i], v);
        }
        fflush(stdout);
    }

    if (2 * total > hfree) {
        fprintf(stderr,
                "rank %d: need %.2f GiB of device memory but only %.2f GiB "
                "is free on device %d of %d visible. Launch with one GCD per "
                "rank (--gpus-per-task=1 --gpu-bind=closest) or lower --mb.\n",
                me, 2.0 * total / (1024.0 * 1024 * 1024),
                (double)hfree / (1024.0 * 1024 * 1024), dev, ndev);
        MPI_Abort(MPI_COMM_WORLD, 2);
    }
    void *sbuf = NULL, *rbuf = NULL;
    HIP_CHECK(hipMalloc(&sbuf, total));
    HIP_CHECK(hipMalloc(&rbuf, total));
    HIP_CHECK(hipMemset(sbuf, me & 0xff, total));
    HIP_CHECK(hipMemset(rbuf, 0, total));
    HIP_CHECK(hipDeviceSynchronize());

    MPI_Request *reqs = malloc(sizeof(MPI_Request) * 2 * (size_t)world);
    if (!reqs) { fprintf(stderr, "out of host memory\n"); MPI_Abort(MPI_COMM_WORLD, 1); }

    /* Graduated pairwise handshake and link census.
     *
     * Round r pairs this rank with (me+r) to send and (me-r) to
     * receive, so over P-1 rounds every ordered pair is exercised
     * exactly once and each round is fully parallel with P/2 disjoint
     * exchanges. Sizes climb from 1 kB to the production payload, so
     * per-peer state is established on the eager path long before any
     * rendezvous-sized message is attempted.
     *
     * The timing of each round is that rank's round-trip to one peer at
     * one size, so the result is a row of a P x P x N bandwidth map.
     * Aggregates are reduced across ranks; the full matrix is only
     * gathered when it is small enough to be useful. */
    if (handshake) {
        static const size_t sizes[] = {
            1024, 8192, 65536, 524288, 2097152, 8388608, 0 };
        int nsz = 0;
        while (sizes[nsz]) nsz++;
        double *row = calloc((size_t)nsz * (size_t)world, sizeof(double));
        if (!row) { fprintf(stderr, "handshake alloc failed\n"); MPI_Abort(MPI_COMM_WORLD, 3); }
        if (me == 0) {
            printf("handshake: %d sizes x %d rounds, pairwise\n", nsz, world - 1);
            printf("%12s %12s %12s %12s %12s\n",
                   "size_B", "min_GB/s", "median_GB/s", "max_GB/s", "slowest_pair");
            fflush(stdout);
        }
        for (int k = 0; k < nsz; k++) {
            size_t sz = sizes[k];
            if (sz > bytes_per_peer) sz = bytes_per_peer;
            for (int r = 1; r < world; r++) {
                int dst = (me + r) % world;
                int src = ((me - r) % world + world) % world;
                MPI_Request rq[2];
                double t = MPI_Wtime();
                MPI_Irecv((char *)rbuf + (size_t)src * bytes_per_peer,
                          (int)sz, MPI_BYTE, src, 11, MPI_COMM_WORLD, &rq[0]);
                MPI_Isend((char *)sbuf + (size_t)dst * bytes_per_peer,
                          (int)sz, MPI_BYTE, dst, 11, MPI_COMM_WORLD, &rq[1]);
                MPI_Waitall(2, rq, MPI_STATUSES_IGNORE);
                double dt = MPI_Wtime() - t;
                row[(size_t)k * world + dst] = dt > 0 ? sz / dt / 1e9 : 0.0;
            }
            /* Reduce this size across every pair in the job. */
            double lo = 1e30, hi = 0.0, sum = 0.0;
            int cnt = 0, slow = -1;
            for (int p = 0; p < world; p++) {
                if (p == me) continue;
                double v = row[(size_t)k * world + p];
                if (v <= 0) continue;
                if (v < lo) { lo = v; slow = p; }
                if (v > hi) hi = v;
                sum += v; cnt++;
            }
            struct { double v; int rank; } linmin = { lo, me }, gmin;
            double gsum = 0, ghi = 0; int gcnt = 0;
            MPI_Allreduce(&linmin, &gmin, 1, MPI_DOUBLE_INT, MPI_MINLOC, MPI_COMM_WORLD);
            MPI_Allreduce(&sum, &gsum, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
            MPI_Allreduce(&hi, &ghi, 1, MPI_DOUBLE, MPI_MAX, MPI_COMM_WORLD);
            MPI_Allreduce(&cnt, &gcnt, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
            int slow_peer = slow;
            MPI_Bcast(&slow_peer, 1, MPI_INT, gmin.rank, MPI_COMM_WORLD);
            if (me == 0) {
                printf("%12zu %12.3f %12.3f %12.3f   rank %d -> %d\n",
                       sz, gmin.v, gcnt ? gsum / gcnt : 0.0, ghi,
                       gmin.rank, slow_peer);
                fflush(stdout);
            }
            if (sz >= bytes_per_peer) break;
        }
        free(row);
        if (me == 0) { printf("handshake complete\n"); fflush(stdout); }
    }

    /* Warm-up exchanges at a size below the rendezvous threshold. */
    if (warm_rounds > 0) {
        if (me == 0) {
            printf("warm-up: %d rounds at %zu B/peer (eager path)\n",
                   warm_rounds, warm_bytes);
            fflush(stdout);
        }
        for (int w = 0; w < warm_rounds; w++) {
            int n = 0;
            for (int p = 0; p < world; p++) {
                if (p == me) continue;
                MPI_Irecv((char *)rbuf + (size_t)p * bytes_per_peer,
                          (int)warm_bytes, MPI_BYTE, p, 9,
                          MPI_COMM_WORLD, &reqs[n++]);
            }
            for (int p = 0; p < world; p++) {
                if (p == me) continue;
                MPI_Isend((char *)sbuf + (size_t)p * bytes_per_peer,
                          (int)warm_bytes, MPI_BYTE, p, 9,
                          MPI_COMM_WORLD, &reqs[n++]);
            }
            MPI_Waitall(n, reqs, MPI_STATUSES_IGNORE);
        }
        if (me == 0) { printf("warm-up complete\n"); fflush(stdout); }
    }

    MPI_Barrier(MPI_COMM_WORLD);

    if (stagger_ms > 0) {
        srand((unsigned)(me * 2654435761u));
        struct timespec ts;
        long ns = (long)((rand() / (double)RAND_MAX) * stagger_ms) * 1000000L;
        ts.tv_sec = ns / 1000000000L;
        ts.tv_nsec = ns % 1000000000L;
        if (me == 0) {
            printf("stagger: each rank waits up to %d ms before starting\n",
                   stagger_ms);
            fflush(stdout);
        }
        nanosleep(&ts, NULL);
    }

    double t0 = MPI_Wtime();

    for (int r = 1; r <= rounds; r++) {
        if (collective) {
            /* Includes the self block, which the point-to-point loop
             * skips: one peer's worth more volume out of P, and a local
             * copy rather than a message. */
            MPI_Alltoall(sbuf, (int)bytes_per_peer, MPI_BYTE,
                         rbuf, (int)bytes_per_peer, MPI_BYTE,
                         MPI_COMM_WORLD);
        } else {
        int n = 0;
        for (int p = 0; p < world; p++) {
            if (p == me) continue;
            MPI_Irecv((char *)rbuf + (size_t)p * bytes_per_peer,
                      (int)bytes_per_peer, MPI_BYTE, p, 7,
                      MPI_COMM_WORLD, &reqs[n++]);
        }
        for (int p = 0; p < world; p++) {
            if (p == me) continue;
            MPI_Isend((char *)sbuf + (size_t)p * bytes_per_peer,
                      (int)bytes_per_peer, MPI_BYTE, p, 7,
                      MPI_COMM_WORLD, &reqs[n++]);
        }
        /* This is the call that fails. */
        MPI_Waitall(n, reqs, MPI_STATUSES_IGNORE);
        }

        if (me == 0 && (r == 1 || r % report_every == 0)) {
            printf("round %5d  elapsed %7.1f s\n", r, MPI_Wtime() - t0);
            fflush(stdout);
        }
    }

    MPI_Barrier(MPI_COMM_WORLD);
    if (me == 0)
        printf("PROBE OK  %d rounds in %.1f s\n", rounds, MPI_Wtime() - t0);

    free(reqs);
    HIP_CHECK(hipFree(sbuf));
    HIP_CHECK(hipFree(rbuf));
    MPI_Finalize();
    return 0;
}
