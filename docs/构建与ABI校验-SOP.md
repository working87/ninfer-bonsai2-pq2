# 构建与 ABI 校验 · SOP（②③ 档 / ninfer 线）

> **这份是可执行的流程单**：从"干净机器"到"引擎能跑 + 能验明它没被改坏"。
> 前置路线判断（走哪条线、要不要改内核）见 `复现手册.md` 第 1 章与 `适配案例集-把引擎搬到你的显卡.md`。

---

## §1 环境准备（Windows 为例）

| 件 | 要求 | 备注 |
|---|---|---|
| 编译器 | **MSVC**（VS 2022 / BuildTools 均可） | 需要 `vcvars64.bat` |
| CMake | **≥ 3.28**（我们用 **4.3.1-msvc1**） | VS 自带的那份在 `…\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe` ✅ |
| Ninja | 任意近期版本 | 也可用 VS 生成器 |
| CUDA | **≥ 13.1**（树里硬性门：`VERSION_LESS 13.1` 直接 `FATAL_ERROR`） | 我们用的是 **13.3**（`nvcc 13.3.33`）✅ |

**两条铁律（都真踩过）**：

1. **构建路径必须纯 ASCII**。非 ASCII 会让 CMake 报
   `Unable to (re)create the private pkgRedirects directory: …/01-???-…`（中文被降级成 `?`）⇒ **先把树复制到一个纯 ASCII 路径（例如 `D:\build\ninfer-tree` 这种）再编**。
2. **`call vcvars64.bat` 与 `cmake` 必须在同一个批处理进程内**，且**先 call 后 cmake**。

---

## §2 依赖获取（网络受限时）

本机实测：`github.com` **直连不通**（curl 超时），但以下通道可用 ✅：

| 通道 | 用法 |
|---|---|
| **gh-proxy 中转** | `https://gh-proxy.com/https://github.com/<owner>/<repo>/…`（文件下载 + `api.github.com`） |
| jsdelivr CDN | `https://cdn.jsdelivr.net/gh/<owner>/<repo>@<branch>/<path>`（取仓库原文） |
| 官方 API | `https://api.github.com/repos/<o>/<r>/releases/latest`（**可用**，即使 `github.com` 不通） |

> **经验**：大文件走中转时用 **curl + 断点续传**（`-C -`）并分批重试，一次长跑容易被中途掐断。

---

## §3 配置与编译

**把下面存成 `build.bat`（**纯 ASCII**，不要写中文注释）**：

```bat
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set "CUDA_PATH=E:\cuda-13.3"
set "PATH=%CUDA_PATH%\bin;%PATH%"
set "CMAKE=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

REM 40 系用 89；50 系用 120a（只允许这两个值）
"%CMAKE%" -S "D:\build\ninfer-tree" -B "D:\build\out" -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_ARCHITECTURES=89

ninja -C "D:\build\out" -j 32
```

**要点**：

- **新建构建目录**（换架构/换 CUDA 后必做，别复用旧缓存）✅
- `CMAKE_CUDA_ARCHITECTURES` 只接受 **`120a` 或 `89`**，其它值 CMake 直接报错（错误原文见 §8）
- 产物：`out\ninfer-serve.exe`（我们的参考件 **251.9 MB**）

---

## §4 ★ ABI 校验 SOP（**换过 DLL / 换过编译器就该跑**）

**用途**：证明"引擎需要的东西，新二进制确实提供"。我们在**把 FFmpeg 从 GPLv3 构建换成 LGPLv3 构建**时就是靠这套过的：**34 个导入符号全部命中，缺失 0** ✅。

```powershell
# 1) 取引擎的导入表（需要 VS 的 dumpbin）
$db  = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\<版本>\bin\Hostx64\x64\dumpbin.exe"
$exe = "D:\pkg\engine\ninfer-serve.exe"

$need = @{}; $cur = ''
foreach($line in ((& $db /imports $exe 2>&1) -join "`n" -split "`n")){
  $l = $line.TrimEnd()
  $h = [regex]::Match($l,'^\s*(\S+\.dll)$')          # 依赖 DLL 行
  if($h.Success){ $cur = $h.Groups[1].Value.ToLower(); continue }
  $s = [regex]::Match($l,'^\s+([0-9A-Fa-f]+)\s+([A-Za-z_][A-Za-z0-9_]*)$')   # 符号行
  if($s.Success -and $cur){ if(-not $need[$cur]){ $need[$cur]=@() }; $need[$cur]+=$s.Groups[2].Value }
}

# 2) 逐个比对新 DLL 的导出表
foreach($dll in $need.Keys){
  $p = "D:\pkg\engine\$dll"; if(-not (Test-Path $p)){ "缺文件: $dll"; continue }
  $exp = @(); foreach($l in ((& $db /exports $p 2>&1) -join "`n" -split "`n")){
    $m = [regex]::Match($l.TrimEnd(),'^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]{8}\s+(\S+)$'); if($m.Success){ $exp += $m.Groups[1].Value }
  }
  $miss = $need[$dll] | Sort-Object -Unique | Where-Object { $exp -notcontains $_ }
  "{0,-20} 需 {1,3} | 导出 {2,4} | 缺 {3} {4}" -f $dll, ($need[$dll] | Sort-Object -Unique).Count, $exp.Count, $miss.Count, $(if($miss){'-> ' + ($miss -join ', ')}else{'OK'})
}
```

**判据**：**"缺 0"** 才算换装成功。**只看版本号相同是不够的** —— 大版本一致但导出集不同照样起不来。

**注意**：dumpbin 的输出里，依赖 DLL 行有 4 空格缩进、符号行是"十六进制序号 + 名字"，正则必须按这个形状写（否则会解析出 0 个符号，我们踩过）✅

---

## §5 冒烟与就绪判据（编完先别测速）

```bat
REM 1) 先看它认不认参数（不加载模型，秒回）
ninfer-serve.exe --help

REM 2) 小上下文真起一次（别一上来就 262144）
ninfer-serve.exe "D:\pkg\model\xxx.ninfer" ^
  --host 127.0.0.1 --port 18080 ^
  --max-context 4096 --kv-capacity 4096 --kv-dtype fp8 --no-thinking
```

**成功的样子**（我们实测的日志顺序）✅：

```
INFO  weights ready | 6.70 GiB | 3.9s | 1.70 GiB/s
INFO  pinning host KV | 8.00 GiB
INFO  CUDA graphs ready | 1.9s
INFO  engine ready | qwen3.8-27b/groupwise-int | total 8.9s
INFO  capacity | KV 4,096 tokens, fp8, explicit | pages 64/64 | runtime 617.6 MiB | free 23.3 GiB
INFO  listening on http://127.0.0.1:18080 | model qwen3.8-27b | auth disabled
```

```powershell
curl.exe -s -o NUL -w "%{http_code}" http://127.0.0.1:18080/v1/models   # 期望 200
```

> ⚠️ **`--kv-capacity` 写小了会被拒**：`kv_capacity is outside the usable range for max_context and max_concurrency`（我们踩过）⇒ `--max-context` 与 `--kv-capacity` 要**一起**给。

---

## §6 把新二进制装回包里（落地流程）

1. **备份**旧的 `engine\` 整个目录；
2. 替换 `ninfer-serve.exe`（DLL 若也换过，一并替换）；
3. **跑一遍 §4 的 ABI 校验**；
4. **跑一遍 §5 的冒烟**（到 `listening` + HTTP 200）；
5. **更新清单**：`SHA256SUMS.txt` 里对应条目的哈希（否则别人校验会失败）；
6. 若动了 `src-tree\`，**必须重建** `src-tree-MANIFEST.sha256`（它是逐文件清单）。

> **运行时不需要装 CUDA Toolkit**：引擎用的是**驱动侧** CUDA 运行库（`nvcuda.dll` / `nvcudart_hybrid64.dll`）—— 我们实测在 PATH 只有 CUDA **12.8** 的机器上也能起到 `listening` ✅。
> 脚本里的 `CUDA_BIN` 只是**防御性**设置：仅在报 `0xC0000135` 时才需要指向你的 CUDA `bin`（注意某些安装把运行库放在 `bin\x64\`，脚本已两个位置都探）。

---

## §7 shared 预算核算（小卡必读）

| 规则 | 数值 | 说明 |
|---|---|---|
| sm_86 / sm_89 **静态** shared 上限 | **48 KiB** | 两档**相同**（别以为 30 系更宽松）✅ |
| sm_89 **动态** shared opt-in 上限 | **101,376 B** | 用 `cudaFuncAttributeMaxDynamicSharedMemorySize` 申请 ✅ |
| sm_120 | 静态上限**被抬高** | 所以上游按高内存 schedule 写，小卡要自己重排 |

**算法**：`静态 shared ≈ tile 参数 × 元素宽度 × 双缓冲系数`。两个真实对照 ✅：

| 内核 | 原配置 | 占用 | 改法 | 改后 |
|---|---|---|---|---|
| `dynamic_grouped_conv` tile-40 | 8 warps | **49,664 B**（超 48 KiB） | → 4 warps | **24,832 B** |
| `linear_swiglu` dflash2 mma | `BK=128` | **50,176 B** | → `BK=64` | **25,600 B** |

**报错长这样**：`ptxas error : Entry function … uses too much shared data (0xc200 bytes, 0xc000 max)`。

---

## §8 常见失败对照表

| 症状 / 报错 | 真因 | 处方 |
|---|---|---|
| `Unable to (re)create the private pkgRedirects directory: …/01-???-…` | **构建路径含非 ASCII** | 换纯 ASCII 路径 |
| `NInfer requires CUDA 13.1 or newer; found …` | CUDA 版本门 | 升 CUDA（≥13.1），或换 `CUDA_PATH` |
| `NInfer supports CMAKE_CUDA_ARCHITECTURES=120a or 89; got ''` | 架构值非法 | 只给 `120a` 或 `89` |
| `ptxas error … 0xc200 bytes, 0xc000 max` | 静态 shared 超 48 KiB | 见 §7 |
| 一堆**未定义符号**（`nvfp4`/`k8v4`/`w8` 相关） | 非 120 构建缺 stub | 确认 `ops/nvfp4_w4a4_stubs.cpp`、`ops/sm120_kv_stubs.cpp`、`ops/w8_sm120_stubs.cpp` 在树内且被 CMake 引用 |
| 换架构后行为诡异 | 复用了旧构建目录 | **新建目录**重配 |
| `0xC0000135`（引擎瞬退） | 缺 CUDA 运行库 | 设 `CUDA_BIN`；本包一般不需要 |
| 起了服务但速度只有个位数 t/s | 疑似**静默回退 CPU** | 查日志 `CPU model buffer size`（排错篇 §4.1） |
| 换了 CUDA DLL 但行为没变 | 内核已编进二进制 | **必须重编**，换 DLL 无效 |

---

## §9 一页速查

```
[ ] ASCII 路径
[ ] vcvars 与 cmake 同一个批处理进程
[ ] CUDA ≥ 13.1，arch 只给 120a 或 89
[ ] 新建构建目录（不复用）
[ ] configure 无 FATAL
[ ] ninja 跑到 100%
[ ] dumpbin 导入/导出比对：缺 0
[ ] 冒烟：--help → 小上下文起服务 → listening → curl 200
[ ] 装回包：备份 → 替换 → 复验 ABI → 重算 SHA256SUMS（+ 重建 src-tree 清单）
[ ] 长提示 + 长输出测速（短提示 / 单 token 不算数）
```


---

# §10 ★ 树里**自带**的构建脚本（先看这个，别急着手写）

源码树根目录已有现成脚本，**默认跑得动的机器上直接用它们**：

| 脚本 | 用途 |
|---|---|
| **`build_v1.0.8.bat`** | **主脚本**（v1.0.8 = 上游 `b88c0f6f` + fork ports 2026-09-09） |
| `build_v1.0.7.bat` | 上一版 |
| `build_windows.bat` / `build_vision_windows.bat` | 纯文本 / 开视觉 |
| `start_4090.bat` · `download_model.bat` | 起服务 / 取权重 |

**主脚本做了什么（读源码确认过）** ✅：

```
第 19–22 行  vcvars64 ← 写死 VS2022：BuildTools → Community → Enterprise → Professional
第 27 行     Ninja   ← 写死 VS2022 BuildTools 的 CMake 扩展目录
第 29–30 行  cmake -B <build> -S . -G Ninja -DCMAKE_CUDA_ARCHITECTURES=89 \
                   -DNINFER_ENABLE_AVX2=ON -DNINFER_BUILD_MEDIA_ACQUIRE=ON -DCMAKE_BUILD_TYPE=Release
第 32 行     cmake --build <build> -j 32
第 36–43 行  把 apps\*.exe 与 ffmpeg\bin\ 的 5 族 DLL 拷到构建目录根（运行期布局）
```

## §10.1 ⚠️ 三个硬编码点（换机器最常见的失败）

| 项 | 脚本写死 | 症状 / 处方 |
|---|---|---|
| **MSVC** | `Visual Studio\2022\…` 四条路径 | 装的是 **VS 2022 之外**的版本（如 VS 17.x 以外的 **VS 18 / 2026**、或只装了 BuildTools 却不是那个路径）⇒ `[cfg] vcvars exit=1` → **`exit /b 90`**。**处方**：改第 19–22 行的路径，或**直接用 §3 的手写命令**（本机实测：VS 18 BuildTools 在 `…\Microsoft Visual Studio\18\BuildTools\…`，脚本里的四个候选**都不存在**） |
| **Ninja** | 只在 VS2022 BuildTools 下找 | PATH 里没有 ninja ⇒ `cmake … -G Ninja` 报找不到生成器。**处方**：把你想用的 ninja 目录加进 PATH |
| **CUDA** | **脚本里不设**（假定已在 PATH） | 报 CUDA 版本门（<13.1）。**处方**：自己 `set CUDA_PATH=…` 并把它加进 PATH（见 §3） |

## §10.2 ★ 别删 `ffmpeg\`（构建**和**运行都依赖它）

- **构建期**：`CMakeLists.txt` 链接 `${PROJECT_SOURCE_DIR}/ffmpeg/lib`（`avcodec/avformat/avutil/swscale/swresample`），头文件在 `ffmpeg/include`。
- **运行期**：脚本第 39–43 行把 `ffmpeg\bin\` 的 DLL **拷到构建目录**，缺了引擎起不来。
- **⇒ 这就是我们 2026-09-26 把整套 `ffmpeg\` 换成 LGPLv3 构建的原因**（原为 GPLv3）；**目录结构与 `.lib/.def` 名完全同构**，CMake 链接不受影响 ✅

> ⚠️ **搬树时别用"跟随链接"的复制方式**：`ffmpeg\` 在原环境曾是目录链接，用会跟随链接的方式复制（或直接解压归档）才不会得到一个空的 `ffmpeg\bin\`。**判据**：复制完 `ffmpeg\bin\` 里能看到 `avcodec-*.dll` 等真文件（本包为**真目录，224 个文件**）。

---

## ★ 数值门的前置纪律：**两个目标必须同批重建**（2026-09-27 实测踩坑）

**症状**：改了引擎源码、只重编 `ninfer-serve`，然后拿**旧的** `ninfer-perplexity` 复核"开关是不是关掉了" ——
数字**原样复现**，你会得出"改了没用/开关无效"的**错结论**。

**真相**：重建 `ninfer-serve` **不会**重链 `ninfer-perplexity`（两个独立目标）。

**判据（照做）**：① 改完源码后，**同一次构建里把 `ninfer-serve` 与 `ninfer-perplexity` 都重建**；
② 复核任何"数值相关"的改动前后，**先核对两个二进制的 mtime/sha**（只重链一个 ⇒ 读数无效）；
③ 数值门读数必须写清用的是**哪一支** `ninfer-perplexity`（sha 前 8 位即可）。

> 同族纪律（一起记）：**编译失败的结论必须自证"编的是哪个文件"** —— 看 rc + 产物 mtime + **编译日志里出现目标文件名**；
> **不要用 obj 尺寸或文件 hash 当"编对了"的证据**（本构建树目标文件不逐位可复现，同源两次编译 hash 不同）。