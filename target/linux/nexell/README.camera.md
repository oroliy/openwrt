# x6818 OV5645 capture

The x6818 device tree connects the original two-lane OV5645 module to the
S5P6818 CSI receiver and VIP DMA engine. `/dev/video0` exposes YUYV capture;
the validated mode is 1280 × 960. RGB LCD simplefb stays enabled, while native
MIPI display remains disabled because it shares the camera block.

The receiver uses the vendor reset, PHY and VIP configuration. STREAMOFF
requests a frame boundary stop, stops VIP_CONFIG before the clipper, stops
CSI before the sensor, and retains one capture-clock reference across capture
sessions. Removal and failed startup release that reference. Buffers reserve
64 bytes beyond the payload for the observed DMA tail; userspace bytesused
remains 2457600 for the validated mode.

## Validation tool

`tests/camera_capture.c` requests four mmap buffers, allows four warmup frames,
checks sixteen complete frames, sequence/timestamps, image variation and
buffer bounds, then verifies STREAMOFF and close. PASS is printed only after
all of these complete. Build it with the configured AArch64 cross compiler:

```sh
$CC -O2 -Wall -Wextra -Werror -static tests/camera_capture.c -o camera-capture
```

Transfer the helper to the board's `/tmp` using an authorized SSH connection,
verify its hash, and run:

```sh
taskset -c 0 /tmp/camera-capture /dev/video0
```

An optional second argument saves the first counted raw YUYV frame on the
board. Exporting that image requires authorization for its local destination.
For repeated testing, run independent capture processes with CPU0 through
CPU7 in rotation. Keep full logs, check every exit status, and reject a changed
boot ID or an interrupted connection. A partial run is not a completed run.

The register, queue, capacity, stop and DTB tests in `tests/test_camera_*.py`
exercise the packaged source and image DTB. They do not replace on-board frame
and close validation. Image quality, other sensor modes and prolonged stress
remain separate acceptance items.

## Platform limitations

The product currently restricts x6818 procd init-script children and the
Dropbear daemon to CPU0–3 as a workaround for observed userspace failures.
PID1, the kernel and explicitly bound capture processes can still use CPU0–7.
The underlying cross-cluster fault has not been identified.
The complete firmware candidate passed 100 capture/close rounds and capture
on every CPU after a normal reboot, with an identifiable room scene. However,
subsequent idle operation still logged abnormal BusyBox ash allocations from
an unidentified background process. Camera validation does not establish
overall system stability, and the service affinity changes remain workarounds. The kernel's
Cortex-A53 843419 workaround alone did not resolve the camera stop failure.

Normal images load existing compat/backports modules and may have taint4096.
Compare against the boot's baseline and verify that camera diagnostics have
not added modules or taint; the RAM rescue image's taint0 is a different case.
