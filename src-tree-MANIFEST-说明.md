# 极速档 src-tree · 完整性核对清单（给 Ubuntu 侧）

**用途**：判定"树缺件"到底是**包缺件**还是**传输丢件**。清单在本机（Windows，包的原件）逐文件生成，可作为基准。

> 基准树：`infer-pkg/models/极速档（ninfer）/src-tree/ninfer-4090w-ternary`
> 清单文件：`src-tree-MANIFEST.sha256`（1,716 条，183,093 B）

---

## 一、基准数字（本机实测）

| 项目 | 实测值 |
|---|---|
| 递归文件总数 | **1,716** |
| 总字节 | **289,089,144**（275.7 MB） |
| 0 字节文件 | **0** |
| 软链接 / 重解析点 | **0** |
| `src/ops/linear/ternary` | **17 个文件**（含 4 个编译单元） |
| 根 `CMakeLists.txt` | 存在；全树 9 个 CMakeLists，共 501 处源文件引用 |

三元线接线位置（`src/CMakeLists.txt`）：

```
346: ops/linear/ternary/ternary_rowsplit_gemm.cu
347: ops/linear/ternary/ternary_dispatch.cpp
348: ops/linear/ternary/ternary_rotation.cu
349: ops/linear/ternary/ternary_rotation.cpp
```

其余 `.cuh/.h`（13 个）由上述 4 个编译单元 `#include` 拉取，不需要单列。

---

## 二、在 Ubuntu 上这样核对

```bash
cd <src-tree 的父目录>              # 里面应当只有 ninfer-4090w-ternary/
find . -type f | wc -l              # 期望 1716
du -sb .                            # 期望 289089144
sha256sum -c src-tree-MANIFEST.sha256 2>&1 | tail -3    # 期望 "1716/1716 OK"
```

**判定**：

- `1716/1716 OK` → 包没缺件，问题在别处（编译环境、参数、架构）
- 少于 1,716 条，或出现 `FAILED` / `No such file` → **传输丢件**，按下面重传
- 数量对但哈希不符 → 中间被改过（编辑器/换行/解压工具改写）

## 三、目录级快速对照（不想跑哈希时）

```bash
for d in src/ops/*/; do printf "%-34s %s\n" "$d" "$(find "$d" -type f | wc -l)"; done
```

基准值（本机实测，供逐行比对）：

| 目录 | 文件数 | 目录 | 文件数 |
|---|---|---|---|
| src/ops/attn_input_proj | 31 | src/ops/linear | 117 |
| src/ops/candidate_selector | 4 | src/ops/linear_add | 29 |
| src/ops/common | 13 | src/ops/linear_attention | 16 |
| src/ops/context_kv_materialize | 3 | src/ops/linear_pair | 8 |
| src/ops/dynamic_grouped_conv | 9 | src/ops/linear_swiglu | 28 |
| src/ops/gdn_gating_proj | 6 | src/ops/linear_topk | 11 |
| src/ops/gdn_input_proj | 36 | src/ops/rmsnorm_rope | 5 |
| src/ops/kernel | 30 | src/ops/softmax_attention | 39 |
| src/ops/kvmem | 37 | src/ops/sparse_moe | 10 |
| src/ops/kv_cache | 13 | src/ops/wrapper | 35 |
| src/ops/launcher | 52 | include/ninfer/ops | 46 |

---

## 四、重传建议（中文目录名是隐患）

包里的分层目录名含中文与全角括号（`极速档（ninfer）`）。用 zip / scp / 某些 GUI 工具在非 UTF-8 locale 下传输，会出现**部分文件丢失或路径错位**——这正是"少了约 250 个文件"的典型形态。若核对不通过，请这样重传：

```bash
# 方式一：rsync 校验式同步（推荐）
rsync -av --checksum --progress "极速档（ninfer）/src-tree/" ubuntu:/dest/src-tree/

# 方式二：先打包再传（避免逐文件编码问题）
tar -cf src-tree.tar "src-tree"        # 在 极速档（ninfer）/ 下执行
scp src-tree.tar ubuntu:/dest/ && ssh ubuntu 'cd /dest && tar -xf src-tree.tar'
```

传完再跑一次第二节的三条命令；`1716/1716 OK` 才算到位。

---

## 五、附：CMake 引用核查方法（避免误判）

**不要**用"CMakeLists 里出现的字符串"判定缺件——注释里也会写文件名。本机核查时，`src/CMakeLists.txt` 第 73/88/102/103/150/156/162/171/175/179/187/200/414 行都只是**注释**（说明性引用），按字符串扫会得出"14 个文件缺失"的假阳性。

正确做法：

1. 只看 `add_library` / `target_sources` 区块内的条目；
2. 相对路径的基准是**该 CMakeLists 所在目录**（`src/CMakeLists.txt` 里的 `ops/...` ⇒ `src/ops/...`）；
3. 拿不准就 `cmake -S <tree> -B <build> -G Ninja -DCMAKE_CUDA_ARCHITECTURES=89` 跑一次 configure：CMake 会在配置阶段直接报出真正找不到的源文件。
