// phxdec_inject.dylib: test loader (DYLD_INSERT_LIBRARIES): registers the VCN decoder in this process at load
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <os/log.h>
#include <unistd.h>
__attribute__((constructor)) static void go(void) {
    const char *p = getenv("PHXDEC_LIB");
    if (!p) p = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU/NVMTLDriver.bundle/Contents/MacOS/libphxdec_hevc.dylib";
    void *h = dlopen(p, RTLD_NOW | RTLD_LOCAL);
    int (*reg)(void) = h ? (int (*)(void))dlsym(h, "phxdec_register") : 0;
    const int r = reg ? reg() : -1;
    os_log(OS_LOG_DEFAULT, "phxdec_inject[%{public}s %d]: %{public}s -> %d %{public}s", getprogname(), getpid(), p, r, h ? "" : dlerror());
}
