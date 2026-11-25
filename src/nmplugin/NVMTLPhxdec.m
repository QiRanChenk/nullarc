// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
/* Included by NVMTLDevice.m: registers the VCN VideoToolbox decoder (libphxdec_hevc.dylib next to this plugin, with
   its FFmpeg libraries and its own RADV build nvmtl/libvulkan_radeon_vcn.dylib) in Metal processes. Adapted from
   Vermilion's src/metal-plugin/NVMTLPhxdec.m (RX 7900 XT) for Phoenix. */
// H.264 / HEVC / AV1 on VCN 4.0.2. The client process picks the decoder from its own registry, so it registers in
// every Metal process but WindowServer. Off with NVMTL_PHXDEC=0 or the file nvmtl/phxdec-off next to the plugin's
// bundle. A session it cannot serve (VCN not up) fails StartSession and VideoToolbox falls back to Apple's decoder.
#include <libgen.h>
static void nvmtl_phxdec_register(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *me = getprogname();
        const char *e = getenv("NVMTL_PHXDEC");
        if (!strcmp(me, "WindowServer")) return;
        Dl_info di;
        if (!dladdr((const void *)nvmtl_phxdec_register, &di) || !di.dli_fname) { nvlog("phxdec: dladdr failed"); return; }
        char dir[1024], path[1200], off[1300];
        strlcpy(dir, di.dli_fname, sizeof dir);
        const char *d = dirname(dir);
        snprintf(path, sizeof path, "%s/libphxdec_hevc.dylib", d);
        snprintf(off, sizeof off, "%s/../../../nvmtl/phxdec-off", d);
        if ((e && e[0] == '0') || access(off, F_OK) == 0) { nvlog("phxdec: off (NVMTL_PHXDEC=0 or phxdec-off) - not registering in %s", me); return; }
        if (access(path, R_OK) != 0) return;   // not installed
        void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!h) { nvlog("phxdec: dlopen %s FAILED: %s", path, dlerror()); return; }
        int32_t (*reg)(void) = (int32_t (*)(void))dlsym(h, "phxdec_register");
        if (!reg) { nvlog("phxdec: %s has no phxdec_register", path); return; }
        const int32_t st = reg();
        nvlog("phxdec: VCN decoder %s in %s (-> %d, rating 1000, %s)", st ? "NOT registered" : "REGISTERED", me, (int)st, path);
    });
}
