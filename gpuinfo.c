/* What does each rank actually see? One line per rank. */
#include <mpi.h>
#include <hip/hip_runtime.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int me, world; MPI_Comm_rank(MPI_COMM_WORLD,&me); MPI_Comm_size(MPI_COMM_WORLD,&world);
    int ndev=0; hipGetDeviceCount(&ndev);
    const char *loc=getenv("SLURM_LOCALID"), *vis=getenv("ROCR_VISIBLE_DEVICES");
    int dev=(ndev>1&&loc)?(atoi(loc)%ndev):0;
    hipSetDevice(dev);
    size_t f=0,t=0; hipMemGetInfo(&f,&t);
    char host[64]; gethostname(host,sizeof host);
    printf("rank %4d host %-12s localid %-3s ndev %d dev %d free %6.2f GiB total %6.2f GiB ROCR=%s\n",
           me, host, loc?loc:"-", ndev, dev, f/1073741824.0, t/1073741824.0, vis?vis:"-");
    fflush(stdout);
    MPI_Finalize(); return 0;
}
