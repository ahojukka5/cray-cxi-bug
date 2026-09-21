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

#include <mpi.h>
#include <hip/hip_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
    int report_every = 10;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--mb") && i + 1 < argc)
            bytes_per_peer = (size_t)(atof(argv[++i]) * 1024 * 1024);
        else if (!strcmp(argv[i], "--rounds") && i + 1 < argc)
            rounds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--report") && i + 1 < argc)
            report_every = atoi(argv[++i]);
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
               "  rounds=%d  thread_level=%d\n",
               world, (double)bytes_per_peer / (1024 * 1024),
               2.0 * (double)total / (1024.0 * 1024 * 1024), rounds, provided);
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

    MPI_Barrier(MPI_COMM_WORLD);
    double t0 = MPI_Wtime();

    for (int r = 1; r <= rounds; r++) {
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
