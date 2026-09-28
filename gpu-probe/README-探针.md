# ============================================================================
#  gpu-probe -- 读你自己这张卡的真实 SM 数 / cc / 显存（免装 CUDA toolkit）
#
#  为什么要它：引擎里的 kTargetSmCount（源码 src\core\device.h）是**编译期常量**，
#  决定内核的大块波次/占用决策 —— 填错就等于"按别人的卡做调度"。
#  而 nvidia-smi **不报 SM 数**（它只报名字和 compute capability），
#  唯一可靠口径是 CUDA runtime 的 cudaDeviceProp::multiProcessorCount。
#  所以：**要重编之前，先跑这个探针。表只作参考，探针读出来的为准。**
#
#  本目录内容：
#    gpu-probe.exe         自足单文件（静态链接 CUDA runtime，不依赖 cudart64_*.dll）
#    gpu-probe.cu          源码（约 130 行，只读设备属性，不跑任何计算）
#    build-probe.bat       构建脚本（需要 CUDA toolkit + MSVC；两个坑写在里面）
#    README-探针.md        本文件
#
#  用法（在包根目录，exe 就在旁边）：
#      gpu-probe.exe              # 一行 JSON + 一行人可读
#      gpu-probe.exe --json       # 只打 JSON（给脚本吃；自检脚本就是这么用的）
#      gpu-probe.exe --human      # 只打人可读
#
#  它做什么：读 device 0..N-1 的 name / cc / SM 数 / 显存 / regs-per-SM /
#  shared-per-SM / shared-per-block(opt-in) / L2 / 总线位宽 / 理论带宽。
#  **不启动引擎、不分配显存、不跑内核、不写任何文件、不联网**，
#  唯一副作用是 CUDA runtime 初始化（几百毫秒、几十 MiB 上下文）。
#
#  退出码：0 = 读到至少一张卡；1 = 没有 CUDA 设备（没卡 / 没驱动 / 驱动太老）；
#          2 = 有卡但拿不到属性。
#
#  依赖说明（已经核过）：exe 的导入表只有三样 ——
#      kernel32.dll、nvcuda.dll、nvcudart_hybrid64.dll
#  **没有** cudart64_*.dll，**不需要**用户装 CUDA toolkit。nvcuda.dll /
#  nvcudart_hybrid64.dll 随 NVIDIA 显卡驱动一起安装（任何能跑 CUDA 程序的机器都有）。
#
#  本机实测输出（RTX 4080 SUPER，2026-09-27）：
#      {"probe":"gpu-probe/1",...,"device_count":1,"devices":[{"index":0,
#       "name":"NVIDIA GeForce RTX 4080 SUPER","cc":"8.9","sm":80,
#       "vram_mib":32759,"shared_per_block_optin":101376,...}]}
#      device 0: NVIDIA GeForce RTX 4080 SUPER | cc 8.9 | SM=80 | mem=32.0 GiB | ...
#      => for a rebuild:  -DNINFER_SM_COUNT=80   -DNINFER_CUDA_ARCH=89
#
#  怎么判断"要不要重编"：
#    1) 跑 gpu-probe.exe，记下 cc 与 SM；
#    2) 看你打算用的那份引擎**烧的是哪个宏**（用本目录的 buildkit 脚本、
#       或包内 docs\引擎-模型-参数对照表.md §4.8「按卡适配」那一条）；
#    3) 探针读出的 SM ≠ 引擎烧入的 SM_COUNT ⇒ 只有"让这张卡跑到上限"这件事受影响，
#       引擎照跑（**不是能不能用的问题，是调优问题**）；要编就按 §4.8 的判据走
#       （数值门 + 真交替中位数 + 记 sha256 与时间戳）。
#
#  许可：本探针是我们自己写的（不包含任何第三方代码）。随便用。
# ============================================================================
