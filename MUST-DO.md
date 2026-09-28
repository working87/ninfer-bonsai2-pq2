# MUST-DO -- 极速档（ninfer） · 2026-09-27

> **动手前先读这份。** 机器可读版（单一事实源）：`agent\must-do.json`；已做过什么记在 `agent\state.json`。
> 本机这张卡的真实 SM 数用包根 `gpu-probe.exe` 读（**nvidia-smi 不报 SM 数**，只有 CUDA runtime 报）。表只作参考。
> Agent 接口的 doctor / plan / start / bench **每条**都会带上这份清单的摘要 —— 不读文档也躲不掉。

## ★ 「我们的想法不一定全面」条款（冲突裁决与证否优先）

> **我们的文档不是权威，你的当机实测才是。** 凡我们没标出处的内容，一律视为**假设**，不是结论。
>
> 顺序是：**证否优先 → 实测裁决 → 回执沉淀**（不是"以实测为准"这么一句，那样证否那一步容易被跳过）。
>
> 1. **先证否**：遇到我们解释不了的问题或矛盾点，**第一步是把我们的结论当假设去设计能推翻它的最小实验**，用**你自己机器上的实测数据**判断（不要靠引用我们的文档来论证）。
> 2. **实测裁决**：若证否成立、或这个矛盾我们确实解释不了 ⇒ **以当机实测 + 你自己的判断为准**，不必迁就我们的说法。
> 3. **回执沉淀**：但请把回执给我们 —— **矛盾点 + 你的实测证据（命令 + 读数 + 引擎/制品 sha256）+ 你的结论** ⇒ 我们据此改文档、改默认值，并**署名来源**。
> 4. **我们没量过的卡/配置**：不要拿我们的表当答案，用 `gpu-probe.exe` 与最小 A/B 自己量；量不出来就标 `pending`，**不要编数**。
> 5. **判"不改"也要证据**：说"这条对我们没用"时，请给出**同口径的读数**（否则我们会当成噪声/没跑起来）。

## 四句话读懂分类

| 类 | 含义 | 要不要做 |
|---|---|---|
| **A** | 调度：改对了逐位相同、零质量风险 | **必做**（值要在你自己的卡上重扫） |
| **B** | 选档/阈值：会动数值（含权重选择） | 必须过数值门 |
| **C** | 口径与开关：不做就得到假读数 | 必做 |
| **D** | 别做：已证伪，做了是负收益 | **别碰** |
| **E** | 按卡适配（SM 常量）：不影响能不能用，只影响能不能触顶 | 想做就按判据做；不做也能跑 |
| **F** | ★ **A3 提级项**（prefill +31.1%、逐位相同；**代码随包 `sched3-patch\`，引擎里没有 ⇒ 要自己编一支**）+ A1/A2 的【值】重扫（代码通用、值不通用） | **必做**（A3 要一次编译；有引擎后同一二进制用 env 扫；A1/A3 要逐位相同，A2 先过数值门） |

## 按「效果好 + 时间短」排的顺序（**照这个顺序做**）

| 层 | 做什么 | 耗时量级 | 条目 |
|---|---|---|---|
| **0** | 口径与纪律（不做就得到假读数） | 0 成本 | C1 C5 C3 C4 C2 **C6** |
| **1** | 投机后端 / KV 档 / K（一条命令、收益最大） | 0 成本 | B4 B3 |
| **2** | 权重选择（0 成本、避免掉分） | 0 成本 | B5 |
| **3** | 两个阈值（env 可扫、分钟级） | 分钟级 | B1 B2 |
| **4** | ★ **一次编译拿到 A3**（我们卡 prefill +31.1%、逐位相同）+ SM 常量 + 宽档 tile（+ A1/A2 值重扫） | 一次编译 ~20–35 min | **A3** F1 E1 B2b |
| **5** | 要改内核代码（未开工） | 需改码 | E2 A2 |
| **6** | 暂存 / 别做（**A1 已实测零收益、A2 已实测负收益**；D 类已证伪） | 0 成本 | A1 A2 D1 D2 D3 D4 D5 D6 D7 |

> 同一层内按"时间更短"排序。**第 4 层的头条是 A3**（token 轴铺进 `grid.y`）：我们卡实测 **prefill +31.1% 且逐位相同**，**代码已随包（`sched3-patch\`）但引擎里没有 ⇒ 要自己编一支**；同一批编译顺手带上 E1 SM 常量 + B2b 宽档 tile，编完再在同一二进制上重扫 A1/A2 的值。
> **第 6 层另有一条暂存项**：稀疏化 / MoE 化（**未立项，不做**）—— 那份立项书**不随包分发**（只有方向，没有任何实测收益）。

## 清单

| 顺序 | id | 类 | 证据等级 | 项 | 要重编? | 适用 |
|---|---|---|---|---|---|---|
| 1 | **C1** | C | `measured` | 测速口径：--greedy + 长提示(>=1k) + 长输出(>=400) + 丢第一次 + 3 次中位数 | 否 | both |
| 2 | **C5** | C | `measured` | 报数必须带：内容类型 + 接受率 + 提示长度 + 输出长度 + 引擎 sha256 | 否 | both |
| 3 | **C3** | C | `measured` | lm-head-draft：MTP 档默认关，dflash2 档必须开 | 否 | both |
| 4 | **C4** | C | `measured` | --prefill-chunk 保持 1024（别重复扫） | 否 | both |
| 5 | **C2** | C | `measured` | 别关前缀复用（--no-prefix-reuse 只在排错时临时用） | 否 | both |
| 6 | **C6** | C | `measured` | **KVMem（长上下文）技术在引擎里，但默认关闭** —— 别设 `NINFER_TERNARY_KVMEM` / `_WINDOW_ASSEMBLY` / `_SEMANTIC`（详见 §6.5） | 否 | both |
| 10 | **B4** | B | `measured` | K（--draft-tokens）预设 5/7；引擎允许 1..15（dflash/dflash2）/1..5（mtp），K<=7 是**工程**上界（成本悬崖） | 否 | both |
| 11 | **B3** | B | `measured` | KV 档（要速度 fp8 / 要窗口 4-bit） | 否 | both |
| 20 | **B5** | B | `measured` | 权重选择：默认用 base，Swift 只当「省 token 但掉分」的可选项 | 否 | both |
| 30 | **B1** | B | `measured` | int8 档起点（kTernaryS8MinTokens，预设 33） | 否 | both |
| 31 | **B2** | B | `measured` | 宽档门（kTernaryWideMinTokens，预设 41） | 否 | both |
| **38** | **A3** ★ | A | `measured` | **token 轴铺进 grid.y（prefill）：我们卡 prefill +31.1% 且逐位相同；分发包引擎里【没有它】⇒ 按 `sched3-patch\` 自编一支（别再当成「从未做」跳过）** | **是** | both |
| 40 | **F1** | F | `measured` | A1/A2 的【值】重扫（**前置：先有 A3 那支自编引擎**）—— 有引擎后同一二进制就能扫 | 否 | both |
| 41 | **E1** | E | `hypothesis` | 按卡适配：确认你这张卡的 SM 数，决定要不要为本卡重编（先跑 gpu-probe，表只作参考） | **是** | both |
| 42 | **B2b** | B | `pending` | 宽档 tile 宽度（64/128 分界）—— 本包未并入 | **是** | both |
| 50 | **E2** | E | `hypothesis` | 按卡适配（前置）：32 行档要 opt-in 动态共享内存，静态上限只有 49,152 B | **是** | both |
| 51 | **A2** | A | `pending` | K 分片门（T<=8 且 n<=6144 且每片剩 >=4 个 K 步时才沿 K 切） | **是** | both |
| 60 | **A1** | A | `pending` | 小批档行块按 n 分桶（n<=5120 用 16 行 / n>5120 用 32 行） | **是** | both |
| 90 | **D1** | D | `measured` | 别做：用 __launch_bounds__ 的 min-blocks 换占用 | 否 | both |
| 91 | **D2** | D | `measured` | 别做：加宽 small_t 的 tile | 否 | both |
| 92 | **D3** | D | `measured` | 别做：拆 LUT | 否 | both |
| 93 | **D4** | D | `measured` | 别做：整字切片 / 指针上提 | 否 | both |
| 94 | **D5** | D | `pending` | 别做（当默认）：--wddm-evictable-budget（12~16 GB 卡） | 否 | both |
| 95 | **D6** | D | `measured` | 别做：把空闲时钟下测的 TFLOPS/利用率差当收益外推 | 否 | both |
| 96 | **D7** | D | `measured` | 别做：为了 T=1 把解码换到 mma 泳道 | 否 | both |

共 **24** 条（A=3  B=6  C=5  D=7  E=2  F=1）。每条为什么 / 怎么做 / 判据 / 出处，全在 `agent\must-do.json` 的对应 item 里。

## 证据等级分布（一眼分清「实测」与「猜想」）

| 等级 | 条数 | id |
|---|---|---|
| `measured` | 21 | **A3, A1, A2**, C1, C5, C3, C4, C2, **C6**, B4, B3, B5, B1, B2, F1, D1, D2, D3, D4, D6, D7 |
| `hypothesis` | 2 | E1, E2 |
| `pending` | 2 | B2b, D5 |

## 按你的卡看这里（卡 → 必做项 → 证据等级）

> **证据等级**：`measured` 我们自己实测 · `author` 原作者数据（不是我们测的）· `hypothesis` 猜想/未量化 · `pending` 待实测/从未实现。
> **完整内容**（每卡一行：SM + 来源 + applies_to_ids + 预期方向 + 动作）在 `agent\must-do.json` 的 `card_guidance.cards`；用 `gpu-probe.exe` 读出来的 SM 永远优先于本表。

### 50 系

| 卡 | SM | 必做项（id） | 证据等级 |
|---|---|---|---|
| RTX 5090 / 5090 D | 170 | B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 E1 F1 | `measured` |
| RTX 5080 | 84 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 5070 Ti | 70 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 5070 | 48 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |

### 40 系

| 卡 | SM | 必做项（id） | 证据等级 |
|---|---|---|---|
| RTX 4090 | 128 | B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 E1 F1 | `measured` |
| RTX 4090 D | 114 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4080 SUPER | 80 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `measured` |
| RTX 4080 | 76 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4070 Ti SUPER | 66 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4070 Ti | 60 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4070 SUPER | 56 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4070 | 46 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4060 Ti 16G | 34 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4060 Ti 8G | 34 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 F1 | `hypothesis` |
| RTX 4060 | 24 | E1 B4 B3 C1 C2 C3 C4 C5 B1 B2 A1 A2 A3 E2 B5 F1 | `hypothesis` |

### 30 系

| 卡 | SM | 必做项（id） | 证据等级 |
|---|---|---|---|
| RTX 3090 / 3090 Ti | 待实测 | C1 C2 C5 | `hypothesis` |
| RTX 3080 Ti | 待实测 | C1 C2 C5 | `pending` |
| RTX 3080 10G / 12G | 待实测 | C1 C2 C5 | `pending` |
| RTX 3070 Ti | 待实测 | C1 C2 C5 | `pending` |
| RTX 3070 | 待实测 | C1 C2 C5 | `pending` |
| RTX 3060 Ti | 待实测 | C1 C2 C5 | `pending` |
| RTX 3060 12G | 待实测 | C1 C2 C5 | `author` |
| RTX 3060 8G | 待实测 | C1 C2 C5 | `pending` |
| 30 系 · ninfer 解锁路线（框架，不是承诺） | 待实测 | E1 E2 B1 B2 B3 C1 C5 | `pending` |

### 笔记本

| 卡 | SM | 必做项（id） | 证据等级 |
|---|---|---|---|
| 笔记本版（40/50 系 Laptop，RTX 4090/4080/4070/4060/4050 Laptop 等） | 待实测 | E1 C1 C2 C3 C4 C5 B4 B3 B1 B2 E2 F1 | `pending` |

### 省显存

| 卡 | SM | 必做项（id） | 证据等级 |
|---|---|---|---|
| 8~12 GB 省显存档（llama+KVMem，超低显存档） | 待实测 | C1 C2 C5 | `pending` |

## 三条最容易踩的

1. **E1**：包内 `src-tree` 的 `device.h` 现在**已内置** `NINFER_SM_COUNT` 分支（2026-09-27 补的）；但**出货**的 sm_89 引擎（`566F0D0E…`）是按 **128（RTX 4090 级）** 编的、sm_120 引擎（`FE170EB2…`）是按 **170（RTX 5090 级）** 编的 ⇒ 4090 与 5090/5090D 用户**正好**，其余卡都偏（SM 越小偏得越多）。重编后**必须**用 `findstr /c:"NINFER_SM_COUNT=<你的SM>" build\build.ninja` 断言宏进了编译行。
2. **口径**：测速一律 贪心 + 长提示(≥1k) + 长输出(≥400) + 丢第一次 + 3 次中位数，**报数带内容类型、接受率、引擎 sha256**。
3. **别做 D 类**：`__launch_bounds__` 换占用、加宽 small_t tile、拆 LUT、整字切片、T=1 换 mma 泳道 —— 全部实测变慢。
4. **30 系**：ninfer 两条档**今天走不了**（引擎侧无条件 cc 硬门，只接受 8.9/12.0，实测拒绝）；**省显存档（llama.cpp + KVMem）可以走**。解锁 ninfer 需改 cc 门 + amp 档编译，属**待开工**（pending），别当承诺。
5. ★ **F 类（A3 是这一类的头条，而且它不在引擎里）**：A 类三条的**实现**与卡无关，**桶的边界/行数/门阈值是卡的函数**（每 SM 可用带宽 + 占用率 + SM 数）⇒ **值必须在你自己的卡上重扫**。**分发包自带的引擎里这三个 env 一个都没有**（`NINFER_TERNARY_TOKEN_GRID` / `_SMALL_T_ROWS` / `_KSPLIT` 在引擎二进制里 **0 命中**）⇒ **先按 `sched3-patch\` 自编一支**，再用这三个 env 在**你自己的卡**上重扫；A1/A3 必须逐位相同才准算收益，A2 先过数值门（我们卡实测：**A3 prefill +31.1%（口径＝PTQ1 件／均衡档）、A1 零收益、A2 负收益**）。

   ★ **适用范围**：这一项**所有 ninfer 档都要看** —— 极速档 PQ2 / 均衡档 PTQ1 / Swift 微调档 / 志愿者补丁包（PQ2 件已过数值门、**速度待量**；+31.1% 的实测口径是 PTQ1 件）；**省显存档（llama+KVMem）不适用**（那一档不是 ninfer 引擎、没有这个内核，它走 `pr-ptq1-mmv` 那条）；**30 系也不适用**（ninfer 档的 cc 门还没解锁）。

