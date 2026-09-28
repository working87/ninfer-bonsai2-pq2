// gpu-probe.cu -- 读这张卡的真实参数（SM 数 / cc / 显存 / 共享内存上限 / 寄存器），输出机器可读 + 人可读
//
// 为什么有它：引擎里的 kTargetSmCount（src/core/device.h）是**编译期常量**，
// 决定内核的大块波次/占用决策 —— SM 数填错 = 按别人的卡做调度。
// 而 nvidia-smi **不报 SM 数**，只有 CUDA runtime 报。所以"要重编之前先跑它"。
//
// 输出（stdout，第一行机器可读，其余人可读）：
//   line 1: {"probe":"gpu-probe/1","cuda_runtime":"...","device_count":N,
//            "devices":[{"index":0,"name":"...","cc":"8.9","sm":80,"vram_mib":32760,
//                        "shared_per_block_optin":101376,...}]}
//   其余  : device 0: NVIDIA GeForce RTX 4080 SUPER | cc 8.9 | SM=80 | ...
//
// 构建：build-probe.bat（nvcc -arch=sm_89 + 静态链接 CUDA runtime，单文件免装 toolkit）
// 退出码：0 = 读到至少一张卡；1 = 没有 CUDA 设备 / runtime 加载不到；2 = cudaGetDeviceProperties 全失败

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cuda_runtime.h>

// CUDA 13 把 cudaDeviceProp::memoryClockRate 拿掉了，但属性式 API 还在。
// 注意：这里必须写 `enum cudaDeviceAttr` —— 这个 enum 声明在 driver_types.h 里
// 明确是 `enum __device_builtin__ cudaDeviceAttr`，所以**没有** cudaDeviceAttr 这个
// 裸 typedef 名可用（写成裸名会得到 "expected a declaration"，看起来像缺分号）。
static int devattr(int dev, enum cudaDeviceAttr a) {
  int v = -1;
  if (cudaDeviceGetAttribute(&v, a, dev) != cudaSuccess) { return -1; }
  return v;
}

static void jstr(const char* s) {
  putchar('"');
  for (const unsigned char* p = (const unsigned char*)s; *p; ++p) {
    if (*p == '"' || *p == '\\') { putchar('\\'); putchar(*p); }
    else if (*p < 0x20) { printf("\\u%04x", (unsigned)*p); }
    else putchar((char)*p);
  }
  putchar('"');
}

int main(int argc, char** argv) {
  int wantJson = 1, wantHuman = 1;
  for (int i = 1; i < argc; ++i) {
    if (!strcmp(argv[i], "--json"))  { wantHuman = 0; }
    if (!strcmp(argv[i], "--human")) { wantJson = 0; }
    if (!strcmp(argv[i], "--help")) {
      printf("gpu-probe [--json|--human]\n");
      printf("  读本机 NVIDIA 卡的真实 SM 数 / compute capability / 显存 / 共享内存上限。\n");
      printf("  默认同时打印一行 JSON 与一行人可读。--json 只打 JSON（给脚本吃）。\n");
      printf("  没有 CUDA 卡时：打 {\"device_count\":0,...} 并返回 1。\n");
      return 0;
    }
  }

  int n = 0;
  cudaError_t e = cudaGetDeviceCount(&n);
  if (e != cudaSuccess) {
    if (wantJson) printf("{\"probe\":\"gpu-probe/1\",\"device_count\":0,\"error\":\"cudaGetDeviceCount: %s\"}\n", cudaGetErrorString(e));
    else          printf("device_count=0  (cudaGetDeviceCount: %s)\n", cudaGetErrorString(e));
    return 1;
  }

  int rtVer = 0;
  cudaRuntimeGetVersion(&rtVer);

  int ok = 0;
  if (wantJson) {
    printf("{\"probe\":\"gpu-probe/1\",\"cuda_runtime\":\"%d.%d\",\"cuda_runtime_num\":%d,\"device_count\":%d,\"devices\":[",
           rtVer / 1000, (rtVer % 1000) / 10, rtVer, n);
    for (int i = 0; i < n; ++i) {
      cudaDeviceProp p;
      memset(&p, 0, sizeof(p));
      cudaError_t pe = cudaGetDeviceProperties(&p, i);
      if (i) putchar(',');
      if (pe != cudaSuccess) {
        printf("{\"index\":%d,\"error\":\"cudaGetDeviceProperties: %s\"}", i, cudaGetErrorString(pe));
        continue;
      }
      ++ok;
      printf("{\"index\":%d,\"name\":", i); jstr(p.name);
      printf(",\"cc\":\"%d.%d\"", p.major, p.minor);
      printf(",\"sm\":%d", p.multiProcessorCount);
      printf(",\"vram_mib\":%llu", (unsigned long long)(p.totalGlobalMem / (1024ull * 1024ull)));
      printf(",\"regs_per_sm\":%d", p.regsPerMultiprocessor);
      printf(",\"shared_per_sm\":%zu", (size_t)p.sharedMemPerMultiprocessor);
      printf(",\"shared_per_block\":%zu", (size_t)p.sharedMemPerBlock);
      printf(",\"shared_per_block_optin\":%zu", (size_t)p.sharedMemPerBlockOptin);
      printf(",\"max_threads_per_sm\":%d", p.maxThreadsPerMultiProcessor);
      printf(",\"max_threads_per_block\":%d", p.maxThreadsPerBlock);
      printf(",\"warp_size\":%d", p.warpSize);
      printf(",\"l2_mib\":%d", p.l2CacheSize / (1024 * 1024));
      int bus = devattr(i, cudaDevAttrGlobalMemoryBusWidth);
      int mclk = devattr(i, cudaDevAttrMemoryClockRate);
      printf(",\"mem_bus_width\":%d", bus);
      printf(",\"mem_clock_khz\":%d", mclk);
      printf(",\"bw_gbs_theory\":%.1f", (bus > 0 && mclk > 0) ? (double)mclk * 2.0 * (double)bus / 8.0 / 1.0e6 : -1.0);
      printf(",\"async_engines\":%d", p.asyncEngineCount);
      printf(",\"concurrent_kernels\":%d", p.concurrentKernels ? 1 : 0);
      printf(",\"unified_addressing\":%d", p.unifiedAddressing ? 1 : 0);
      printf("}");
    }
    printf("]}\n");
  }

  // Human-readable half is deliberately ASCII-only: the console codepage on a
  // Chinese Windows is 936 (GBK), so a UTF-8 Chinese printf comes out as mojibake.
  if (wantHuman) {
    if (n == 0) printf("device_count = 0  (no CUDA device: no NVIDIA card / no driver / driver too old)\n");
    for (int i = 0; i < n; ++i) {
      cudaDeviceProp p;
      memset(&p, 0, sizeof(p));
      if (cudaGetDeviceProperties(&p, i) != cudaSuccess) continue;
      int bus  = devattr(i, cudaDevAttrGlobalMemoryBusWidth);
      int mclk = devattr(i, cudaDevAttrMemoryClockRate);
      printf("device %d: %s | cc %d.%d | SM=%d | mem=%.1f GiB | regs/SM=%d | shared/SM=%zu | shared/block max=%zu\n",
             i, p.name, p.major, p.minor, p.multiProcessorCount,
             (double)p.totalGlobalMem / 1073741824.0,
             p.regsPerMultiprocessor, (size_t)p.sharedMemPerMultiprocessor,
             (size_t)p.sharedMemPerBlockOptin);
      printf("          bw~%.0f GB/s (%d-bit @ %.1f Gbps) | L2 %d MiB | %d SM x %d threads | warp %d\n",
             (double)mclk * 2.0 * (double)bus / 8.0 / 1.0e6,
             bus, (double)mclk * 2.0 / 1.0e6,
             p.l2CacheSize / (1024 * 1024), p.multiProcessorCount, p.maxThreadsPerMultiProcessor, p.warpSize);
      printf("          => for a rebuild:  -DNINFER_SM_COUNT=%d   -DNINFER_CUDA_ARCH=%d%d\n",
             p.multiProcessorCount, p.major, p.minor);
      if (p.sharedMemPerBlockOptin >= 98304)
        printf("          => shared/block opt-in %zu B >= 98304 B: the 32-row SMALL_T tier can ask for dynamic shared\n",
               (size_t)p.sharedMemPerBlockOptin);
    }
  }

  if (n <= 0) return 1;
  return ok > 0 ? 0 : 2;
}
