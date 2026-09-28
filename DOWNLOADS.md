# DOWNLOADS：大文件下载地址（全部国内源）

git 仓库里没有放大文件。以下文件都在魔搭 ModelScope 上，国内直连，无需登录，支持断点续传。
**按指南判断本机需要哪些，缺啥下啥**，不需要全下。下载后按「放到」一列放好，目录结构就和原包完全一样。

原作者：沈三殊（shensanshu）。引擎由原作者编译，这里只是原样转发。
B站 https://space.bilibili.com/85280961 ；魔搭 https://www.modelscope.cn/models/shensanshu/ninfer-ada-ternary

## 引擎（魔搭 working87/ninfer-bonsai2-pq2-engine）

两份引擎各自只认自己的架构，互相不能替代。先用 `nvidia-smi --query-gpu=compute_cap --format=csv` 查算力。

| 文件 | 用途 | 放到 | 字节 | SHA256 | 下载地址 |
|---|---|---|---|---|---|
| `ninfer-serve.exe` | sm_89，RTX 40 系（cc 8.9） | `engine\` | 264173568 | `566F0D0ED8FF23E0FDBFD66E8B5C8C704228F883E728923E87565766FB2BACB8` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/ninfer-serve.exe |
| `ninfer-serve-sm120.exe` | sm_120，RTX 50 系（cc 12.0） | `engine\` | 198689792 | `FE170EB23FFDBFF5EB9F9D70A390EC639910BEAB420F30DCB937AF2CD0269C42` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/ninfer-serve-sm120.exe |

## FFmpeg dll（同一仓库，两份引擎通用，7 个缺一不可）

引擎运行时必须和 exe 放在同一目录 `engine\`。如果要从源码自己编译，同一批文件还要复制一份到 `src-tree\ninfer-4090w-ternary\ffmpeg\bin\`（原包源码清单 `src-tree-MANIFEST.sha256` 里包含它们）。

| 文件 | 放到 | 字节 | SHA256 | 下载地址 |
|---|---|---|---|---|
| `avcodec-63.dll` | `engine\` | 91181568 | `1A43CF4B22BCE33DFC3853C8373A9FCFF90F532F3B1E34254BA418824D60A4A7` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/avcodec-63.dll |
| `avdevice-63.dll` | `engine\` | 4948480 | `0B4363087576EA75C97082F8D6C54A843660D3FC55069A8E84EF5003888180B7` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/avdevice-63.dll |
| `avfilter-12.dll` | `engine\` | 31195648 | `CC227B1ED66D36482B80D807F198166927B0102E51314847803689B3CBB42C8B` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/avfilter-12.dll |
| `avformat-63.dll` | `engine\` | 22764032 | `8DA0B1708A0E320AAE895474DC48FE76030444D44A72004B2E4CE2FD4C1FC9D7` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/avformat-63.dll |
| `avutil-61.dll` | `engine\` | 3016704 | `00FCD925ECD35A723EF5085EA00B5835D3535C32AB7AC683378FBBB13067A5B6` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/avutil-61.dll |
| `swresample-7.dll` | `engine\` | 734720 | `F63082A912994464C7ABD6187D35D7AF0C58C5D9AF6D86AB93D7C58343CBEDF0` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/swresample-7.dll |
| `swscale-10.dll` | `engine\` | 2332160 | `5D941DC3791ED917650E50C9464A9EFB6237599B9533F005767155EDEFB1EE68` | https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine/resolve/master/engine/swscale-10.dll |

## 模型权重（魔搭 w3c0929/Ternary-Bonsai-2-27B-NInfer，与原包逐位一致）

用哪份、配什么参数，看 `README.md`「启动件总表」和 `agent\AGENT.md` §3。

| 文件 | 用途 | 放到 | 字节 | SHA256 | 下载地址 |
|---|---|---|---|---|---|
| `bonsai2_27b_ternary_v2.ninfer` | 基础制品（PQ2，含视觉塔）；start-8084/8086/8087 用它，开视觉只能用它 | `model\` | 8306927628 | `05BBBF01090C6F61113B54556DAA22AD0B45036A078AF6CD6F02A3FDE47AD76C` | https://www.modelscope.cn/models/w3c0929/Ternary-Bonsai-2-27B-NInfer/resolve/master/bonsai2_27b_ternary_v2.ninfer |
| `bonsai2_27b_ternary_v2-dflash2.ninfer` | 基础制品 + DFlash2 草稿分支；start-8085/8088 用它 | `model\` | 10533733120 | `F66C8300EFF996A58893E7D567A3E000D7B6347F3A72B2124EAC11791720E148` | https://www.modelscope.cn/models/w3c0929/Ternary-Bonsai-2-27B-NInfer/resolve/master/bonsai2_27b_ternary_v2-dflash2.ninfer |

## 下载方法

任何支持断点续传的工具都可以。Windows 自带的 curl 示例（中断后重跑同一条命令会接着下）：

```powershell
curl.exe -L --fail --retry 5 -C - -o model\bonsai2_27b_ternary_v2.ninfer https://www.modelscope.cn/models/w3c0929/Ternary-Bonsai-2-27B-NInfer/resolve/master/bonsai2_27b_ternary_v2.ninfer
Get-FileHash model\bonsai2_27b_ternary_v2.ninfer -Algorithm SHA256
```

**每个文件下完都必须核对 SHA256**，对不上就删掉重下。全部放好后，也可以跑包根的 `自检-搬家.ps1` 一次性核对整个包。

## 其他依赖

- **NVIDIA 驱动**：必需，用户自行安装。运行预编译引擎**不需要** CUDA Toolkit。
- **VC++ 运行库**：Windows 一般自带。引擎报 `0xC0000135` 且确认 dll 齐全时，可以从清华 PyPI 镜像取 `msvc-runtime` 的 wheel，解压后把 `msvcp140*.dll`、`vcruntime140*.dll` 放进 `engine\`：https://pypi.tuna.tsinghua.edu.cn/simple/msvc-runtime/
- **从源码编译**（仅当本机架构没有对应引擎时）：所需工具和步骤见 `08-从零复现方案书（兜底路线）.md`、`docs\兜底方案-从源码自己编译.md`。
