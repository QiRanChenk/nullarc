# video/ — sources and licenses

Most of this directory is ported from **Vermilion** (https://github.com/leolivm/vermilion, commit 9a91901), the
RX 7900 XT derivative of nullarc, and adapted to Phoenix / Hawk Point (VCN 4.0.2, MMHUB 3.0.1). Vermilion's own code
is MIT, Copyright (c) 2026 Vermilion contributors; its full license terms are in its `LICENSE` and `LICENSES/`.

| Path | Origin | License |
|---|---|---|
| `decoder/` | Vermilion `src/video-decoder`; changed here: H.264 (`avc1`/`avc3`), the `phxdec-deny` list, the default and switch paths under PhxGPU, `phxdec_inject.c` (new), `build.sh` | MIT, Copyright (c) 2026 Vermilion contributors; changes MIT, Copyright (c) 2026 QiRanChenk |
| `vcn/vcn_phx_gen.py`, `vcn/vcn_up.sh` | Vermilion `tools/phxctl/vcn_m1_gen.py`, `vcn_up.sh`; layout, fw_shared flags and register sequence redone for Phoenix from a Linux amdgpu trace on this machine | MIT (as above) |
| `vcn/` other scripts, `build.sh`, `install.sh`, `vtcheck.sh` | written for this port | MIT, Copyright (c) 2026 QiRanChenk |
| `mesa/patches/0001-0009` | Cobalt64 (Navi48-MacOS), via Vermilion | MIT, Copyright (c) 2026 Cobalt64 |
| `mesa/patches/0010-0015` | nullarc `mesa-patches-phoenix` 0001-0006, via Vermilion | MIT, Copyright (c) 2026 luuumi-dev and the nullarc contributors |
| `mesa/patches/0016-0017` | Vermilion | MIT, Copyright (c) 2026 Vermilion contributors |
| `mesa/patches/0018-0020` | this port | MIT, Copyright (c) 2026 QiRanChenk |
| `ffmpeg/patches/0001` | Vermilion `patches/ffmpeg` | LGPL-2.1-or-later, as FFmpeg |
| `ffmpeg/patches/0002` | this port | LGPL-2.1-or-later, as FFmpeg |

Register offsets, message formats and sequences follow Linux `amdgpu` (`vcn_v4_0.c`, `amdgpu_vcn.c`, the
`vcn_4_0_0` register headers), Copyright Advanced Micro Devices, Inc., MIT.

The VCN firmware (`amdgpu/vcn_4_0_2.bin`) is not included; `install.sh` downloads it from linux-firmware (commit
f30df53), where it is redistributable under AMD's `LICENSE.amdgpu`.

The built `libavcodec_phx` / `libavutil_phx` are LGPL-2.1-or-later (FFmpeg configured without GPL or nonfree parts);
they are shipped as separate dylibs next to the decoder, which links them dynamically.

The Metal plugin that registers the decoder (`src/nmplugin`, branch `wujie-vcn`) is derived from NullMoth's driver and
is under PolyForm Noncommercial 1.0.0; nothing in this directory is.
