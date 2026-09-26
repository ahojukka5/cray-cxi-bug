#!/bin/bash
# Platform provenance below MPI: kernel, CXI driver, NIC firmware, libcxi,
# libfabric RPMs. Needs no root. Run on the compute node being described.
#   record_platform.sh > evidence/provider/platform-<host>.txt
echo "timestamp: $(date -Is)"
echo "hostname: $(hostname)  slurm_job: ${SLURM_JOB_ID:-none}"
echo "=== os / kernel ==="
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
uname -a
echo "=== rpm: fabric stack ==="
rpm -qa 2>/dev/null | grep -i -E 'cxi|libfabric|cassini|slingshot|kdreg|sl-driver|kfabric|rocm-core|amdgpu' | sort
echo "=== loaded kernel modules ==="
for m in $(lsmod | awk 'NR>1 && /cxi|sbl|sl_|kdreg|kfi|amdgpu/ {print $1}'); do
  printf '%s version=%s srcversion=%s\n' "$m" \
    "$(cat /sys/module/$m/version 2>/dev/null || echo -)" \
    "$(cat /sys/module/$m/srcversion 2>/dev/null || echo -)"
done
echo "=== modinfo cxi_ss1 / cxi_core ==="
for m in cxi_ss1 cxi_core cxi_user; do
  /sbin/modinfo "$m" 2>/dev/null | grep -E '^(filename|version|srcversion|vermagic):'
done
echo "=== CXI devices ==="
ls /sys/class/cxi 2>/dev/null
for d in /sys/class/cxi/cxi*; do
  [[ -e "$d" ]] || continue
  echo "--- $d"
  for f in device/uevent device/vendor device/device device/subsystem_device \
           properties/nid properties/pid_bits properties/cassini_version \
           properties/system_type_identifier properties/uc_nic \
           device/fru/serial_number; do
    [[ -r "$d/$f" ]] && echo "$f: $(tr '\n' ' ' < "$d/$f")"
  done
  ls "$d" 2>/dev/null | tr '\n' ' '; echo
done
echo "=== cxi_stat ==="
command -v cxi_stat && cxi_stat 2>&1 | head -80
echo "=== retry handler service ==="
systemctl list-units 'cxi_rh*' --no-pager 2>&1 | head -10
echo "=== libcxi / libfabric files ==="
for f in /usr/lib64/libcxi.so.1 /opt/cray/libfabric/1.22.0/lib64/libfabric.so.1; do
  echo "$f -> $(readlink -f "$f") sha256=$(sha256sum "$(readlink -f "$f")" | cut -d' ' -f1)"
done
/opt/cray/libfabric/1.22.0/bin/fi_info --version
/opt/cray/libfabric/1.22.0/bin/fi_info -l 2>&1 | head
echo "=== fi_info -p cxi (first entry) ==="
/opt/cray/libfabric/1.22.0/bin/fi_info -p cxi 2>&1 | head -20
echo "=== FI_CXI defaults (fi_info -e, cxi) ==="
/opt/cray/libfabric/1.22.0/bin/fi_info -e 2>/dev/null | grep -A1 -E 'FI_CXI_(RDZV|OFLOW|REQ_BUF|RX_MATCH|DEFAULT_CQ|DEFAULT_TX|MSG_OFFLOAD|SAFE_DEVMEM|CQ_FILL)' | grep -v '^--' | head -60
