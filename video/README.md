# Hardware video decode on VCN 4.0.2 (Phoenix / Hawk Point)

H.264, HEVC and AV1 decode on the 780M's VCN under macOS, exposed to VideoToolbox, so Safari, Chromium-based browsers and
AVFoundation players use it. This directory holds the user-space half and VCN's bring-up. The kernel half (VCN queue,
MMHUB VM, fence fix) is PhxBringup on this branch (`vcn`), and the registration hook is in the Metal plugin on branch
`wujie-vcn` (`src/nmplugin/NVMTLPhxdec.m`). Notes and measurements: luuumi-dev/nullarc#46.

Verified on one machine only: MECHREVO WUJIE15XA (Ryzen 7 8745HS, 1002:1900), macOS 26.7.3, PhxBringup build 47.
VP9 is not done (FFmpeg 7.1 has no vp9_vulkan).

## How it fits together

```
app -> VideoToolbox -> libphxdec_hevc.dylib (registered in-process by the Metal plugin, VTRegisterVideoDecoderWithInfo)
        -> libavcodec_phx (FFmpeg n7.1: h264 / hevc / av1 + Vulkan Video hwaccels)
        -> libvulkan_radeon_vcn.dylib (RADV with Vulkan Video, used directly as the ICD)
        -> PhxBringup user client -> VCN unified ring (MMHUB VM)
```

VCN itself is powered and loaded from user space at boot (`vcn/vcn_up.sh`, the Linux `vcn_v4_0_start_dpg_mode`
sequence driven through `phxctl`'s debug selectors), then handed to the kernel (`debug.phxvcn=1`, `debug.phxmmvm=1`).

## Layout

| Path | What | License |
|---|---|---|
| `mesa/patches/0001-0017` | RADV Darwin backend, Vermilion's series (0001-0009 Cobalt64's, 0010-0015 nullarc's `mesa-patches-phoenix`) | MIT |
| `mesa/patches/0018-0020` | Phoenix: default device and VCN 4.0.2 identity; unmap/free wait for this process's submissions; no compute or transfer queue family | MIT |
| `ffmpeg/patches` | 0001 Vermilion's hevc/vulkan changes for the decoder; 0002 H.264 one picture per access unit with `AV_CODEC_FLAG_LOW_DELAY` | LGPL-2.1-or-later |
| `decoder/` | `libphxdec_hevc.dylib` (VideoToolbox decoder; Vermilion's `src/video-decoder` plus H.264, a per-process deny list, Phoenix paths), `vtdec_test`, `phxdec_inject.dylib`, `vtbundle/` (static plug-in stub, unused here) | MIT |
| `vcn/` | `vcn_phx_gen.py` (writes the ring/IB/fw_shared image and the DPG SRAM list), `vcn_up.sh`, `vcnboot.sh` + `local.vcnboot.plist` (boot), `vcnwake.sh` (after hibernation), `vcnon.sh`, `waitboot.sh`, `gcfd.sh`; `diag/` hang and stall tools | MIT |
| `build.sh`, `install.sh`, `vtcheck.sh` | build from source, install, frame-exact check | MIT |

See `NOTICE.md` for authors and sources.

## Requirements

- nullarc installed and working with acceleration (phxboot, `/Users/Shared/gpu/phxctl/phxctl`).
- Boot-arg `phxdebug=1` (the bring-up uses the debug register and PSP selectors).
- PhxBringup and PhxAccel from this branch, PhxBringup build 47 or later. Builds 38-46 bring VCN up but return wrong
  pictures under load (a fence wait could report a job done before it was queued).
- The Metal plugin from branch `wujie-vcn` (it loads and registers the decoder; without it nothing registers).
- `tools/phxwake` from this branch if hibernation is used (its `phxwake.sh` calls `vcnup/vcnwake.sh`).
- Command Line Tools (x86_64 clang). No Homebrew; `build.sh` downloads everything else at pinned versions.

## Build, install, check

```sh
bash video/build.sh                  # -> video/out (about 2 GB in video/work, 15-30 minutes)
sudo bash video/install.sh
sudo bash /Users/Shared/gpu/vcnup/vcnon.sh   # now, or reboot (local.vcnboot does it at every boot)
sysctl debug.phxvcn debug.phxvcn_stat        # 1, and submits counting up while a video plays
```

Frame-exact check against a software decode (any 8-bit H.264 / HEVC / AV1 clip, decoded whole; long clips find more):

```sh
ffmpeg -i clip.mp4 -pix_fmt nv12 -f framemd5 ref.framemd5     # on any machine with FFmpeg
bash video/vtcheck.sh clip.mp4 <frame count> ref.framemd5 3
```

`vtcheck.sh` uses the freshly built `out/` (no install needed, VCN must be up). To exercise the installed path the way
apps do (the plugin registers the decoder when the process opens its Metal device), run
`VTTEST_METAL=16 out/decoder/vtdec_test <clip> <frames>` without a decoder argument and watch `debug.phxvcn_stat`. On the reference machine a 26,412-frame
AV1 clip gave 7-12 runs of wrong frames per pass with builds 46 and older, and none in six passes with build 47.

To see whether a browser really decodes on VCN, watch `debug.phxvcn_stat` (submit count) while it plays; Chromium's GPU
process writes nothing to the unified log.

## Switches

| Switch | Effect |
|---|---|
| `/Users/Shared/gpu/vcnup/off` | no bring-up at boot or after a wake. Created automatically when a bring-up did not finish |
| `PhxGPU/nvmtl/phxdec-off`, env `NVMTL_PHXDEC=0` | the plugin does not register the decoder (Apple's software decoders run) |
| `PhxGPU/nvmtl/phxdec-deny` | process names, one per line, that keep Apple's decoders |
| `PhxGPU/nvmtl/phxdec-no-avc`, `phxdec-no-av1` | no H.264 / no AV1 registration |
| `PhxGPU/nvmtl/phxdec-pool-bound` | bounded output pool (32 buffers); used on the reference machine |
| env `PHXDEC_LOG=1`, `PHXDEC_ICD=<dylib>` | decoder log on stderr; another RADV build |
| env `RADV_DARWIN_ALL_QUEUES=1` | RADV offers the compute and transfer families again (they hang here, see below) |

`PhxGPU` = `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU`.

## Hazards found on the way

- The kext's compute queue dies after an idle period and the next submit hangs WindowServer through the global wait;
  the decoder's RADV therefore exposes only the general queue.
- The kext does not keep in-flight BOs alive: RADV must wait for its own submissions before unmapping or freeing
  (patch 0019), or the CP fetches an unmapped IB and the GC hub stalls.
- A GC hub page fault without a fault default page stalls the whole GFX engine; `gcfd.sh` sets one for debugging.
- Never read the `*_INVALIDATE_ENG*_SEM` registers or sweep VCN register ranges on a live GPU: a read takes the
  semaphore, and a sweep during decode hung VCN under Linux as well.
- Apps that start before VCN is up decode in software for their lifetime; the boot daemon therefore brings VCN up as
  soon as the GPU is claimed, not when phxboot is done.
- Hardware decode by itself saved no measurable power on a 1080p25 stream on this machine; presenting at 60 instead of
  120 Hz did (boot-arg `phxvbldiv=2`, chip 12.3 W -> 9.4 W).
