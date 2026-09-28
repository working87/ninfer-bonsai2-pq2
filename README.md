# 极速档 · PQ2 — 三元 Bonsai-2-27B on ninfer

## 🙏 鸣谢：原作者沈三殊（shensanshu）

**本项目的原作者是沈三殊（shensanshu）。** 除模型权重外，这里的全部内容都由沈三殊制作和发布，包括部署方案、启动脚本、文档、排错手册、agent 工具链、显卡探针、调度补丁、源码树，以及 ninfer 三元引擎的改造与编译。模型权重的出处见下方「许可与署名」。

**我（working87）只是转发和上传，没有参与创作。** 觉得有用的话，请去原作者主页点赞、关注、投币支持：

- 📺 **B站：** https://space.bilibili.com/85280961
- 🤖 **魔搭 ModelScope：** https://www.modelscope.cn/models/shensanshu/ninfer-ada-ternary

---

## 🤖 交给 AI Agent 部署

把本仓库 clone 到**纯英文路径**，发给 agent（Claude Code、Codex、Cursor 等），说一句“按 AGENTS.md 部署”即可。
agent 会按原作者的指南（`00-从这里开始.md`）在你的机器上探测显卡、选择档位，再按需下载。

git 仓库里没有放大文件，**全部下载地址都在 [DOWNLOADS.md](DOWNLOADS.md)**，都是国内源，附 SHA256，缺啥下啥：

| 内容 | 国内来源 |
|---|---|
| 引擎 `ninfer-serve.exe`（sm_89，40 系）/ `ninfer-serve-sm120.exe`（sm_120，50 系）+ 7 个 ffmpeg dll | 魔搭 [working87/ninfer-bonsai2-pq2-engine](https://www.modelscope.cn/models/working87/ninfer-bonsai2-pq2-engine)（沈三殊编译，原样转发） |
| 模型 `bonsai2_27b_ternary_v2.ninfer`（8.31 GB）/ `…-dflash2.ninfer`（10.53 GB） | 魔搭 [w3c0929/Ternary-Bonsai-2-27B-NInfer](https://www.modelscope.cn/models/w3c0929/Ternary-Bonsai-2-27B-NInfer)（与原包 SHA256 逐位一致） |

下载的文件放回对应目录后，目录结构就和原包完全一样，下文说明全部适用。

### 两种方案：各需要什么、实测多快

两种方案共用同一份引擎：40 系用 `engine\ninfer-serve.exe`，50 系用 `engine\ninfer-serve-sm120.exe`，都要配 7 个 ffmpeg dll。区别在模型和启动件：

| | 方案一：基础档（MTP 投机） | 方案二：DFlash2 档（最快） |
|---|---|---|
| 模型 | `model\bonsai2_27b_ternary_v2.ninfer`（8.31 GB） | `model\bonsai2_27b_ternary_v2-dflash2.ninfer`（10.53 GB） |
| 启动件 | `start-8084.bat`（纯文本，≥16 GB）<br>`start-8086.bat`（开视觉）<br>`start-8087-12g.bat`（12~16 GB 卡） | `start-8085-dflash2.bat`（32K 上下文，≥16 GB）<br>`start-8088-dflash2-128k.bat`（128K 上下文，≥24 GB） |
| 显存 | 运行时 8.54 GiB（开视觉 8.78 GiB） | 权重 9.10 GiB；32K 上下文时全卡约 12.3~12.6 GB |
| 视觉（看图） | ✅ 支持（只能用这份模型） | ❌ 不能和视觉同时开 |

**实测速度**（原作者数据，RTX 4080 SUPER，单路、贪心解码；**同一张卡，内容不同速度能差 3 倍，看数字一定要连着内容和配置看**）：

| 内容 | 不投机 | 方案一 MTP | 方案二 DFlash2 K=7 |
|---|---|---|---|
| 数数字（高度可预测） | 63.7 t/s | 211.9 t/s（接受率 95.0%） | **353.8 t/s**（97.9%） |
| HTML / 代码 | 62.9 t/s | 172.0 t/s（78.0%） | 193.9 t/s（48.1%） |
| 散文 | 62.4 t/s | 88.2 t/s（26.2%） | 112.1 t/s（21.2%） |

- 上表 MTP 一列是 draft 4 的读数。方案一出厂配置是 MTP draft 3，原作者在 16K 上下文、400 token 输出下测得 decode **226.0 t/s**（接受率 81.75%），prefill **2,230 t/s**。
- 志愿者在 RTX 5090 D 上测方案二（未重新编译）：数数字 **512.9 t/s**，散文 154.7 t/s。
- 跨卡绝对值不能直接比，可以按显存带宽折算，见 `00-从这里开始.md`。

**怎么选**：要看图、或者显存小于 16 GB → 方案一；显存 ≥16 GB、要最快 → 方案二；两个都想要就两份模型都下，用不同启动件切换。部署时可以直接告诉 agent 用哪个方案。

> 以下为原包 README 原文。

---

<!-- LICENSE-BLOCK-BEGIN -->

## 许可与署名（★ 先读这一块）

**模型权重：Apache-2.0**（我方口径，按用户要求标注）。**上游许可 / NOTICE 链接见下**；
**若上游社区许可另有附加条款，以上游为准。**

> 已知情况（如实写，不替上游说话）：基座模型卡自带 `NOTICE.md`，其中标的许可名是社区许可
> `prism-bonsai-community`；而微调档来源 `ukisai/Swift-Bonsai-2-GGUF` 在模型卡上标的是 `apache-2.0`。
> 所以本节按 Apache-2.0 标注，同时把上游 NOTICE 原样给出 —— **冲突时以上游为准**。

**本档携带的模型制品（逐个点名）**
- `model\bonsai2_27b_ternary_v2.ninfer`（格式 **PQ2_0**）—— 基座三元制品
- `model\bonsai2_27b_ternary_v2-dflash2.ninfer`（PQ2_0 + 自造 dflash2 注入件）

**上游出处（原作者链接）**
- 基座（Prism ML，三元制品）：https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf
- 基座 NOTICE：https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/NOTICE.md

**署名（请照此标注）**：**Created using Bonsai by Prism ML.** — Bonsai 2 27B © 2026-present Prism ML, Inc.（Apache-2.0）；Built on **Qwen3.8-27B** © 2026 Alibaba Cloud（Apache-2.0）。

**引擎 / 第三方组件（与模型权重分开，各有各的许可，别混成一句）**
- 上游 ninfer 引擎：https://github.com/Neroued/ninfer
- 超低显存档血统的 llama.cpp 分支：https://github.com/PrismML-Eng/llama.cpp
- FFmpeg（`engine\av*.dll` / `sw*.dll`）：**LGPL v3**（本档 `licenses\FFmpeg-LGPLv3.txt`、`licenses\FFmpeg-来源与许可.md`）；若分发的是 GPL 构建，则受 **GPL-3.0** 约束（`licenses\GPL-3.0.txt`）
- llama.cpp / CUDA / KVMem 及全部 vendor 依赖：**见 `licenses\NOTICE.txt`、`licenses\THIRD_PARTY_NOTICES.md` 与 `licenses\` 内其余文件**
  （**本块不替它们声明许可**；以那些文件与各自上游为准）

**完整许可文本**：`licenses\LICENSE-Apache-2.0.txt`（模型权重，Apache-2.0 全文）

<!-- LICENSE-BLOCK-END -->


> **★ 动手前先读 MUST-DO.md / gent\must-do.json（必做调优项，含「按你的卡看这里」与按卡适配）。**
> **一句话**：**27B 的智力，塞进 8 GB 显存的机器里**，prefill 2.2k t/s、decode 226 t/s。
> 这是三档里的**速度档**（另两档：① 纯 llama+KVMem 三元 = 超低显存档；③ PTQ1+ninfer = 均衡档）。

**打包日期**：2026-09-26 ｜ **形态**：离线自足目录，双击即跑 ｜ **跑起来不需要联网**
（本包语言模型**已含视觉塔载荷**，无需另下；只有"要自己从零复现或换路线"时才需下视觉塔独立件，指引见下）

> **署名（Apache-2.0，请照此标注）**：
> **"Created using Bonsai by Prism ML."** — Bonsai 2 27B © 2026-present Prism ML, Inc.（Apache-2.0）
> Built on **Qwen3.8-27B** © 2026 Alibaba Cloud（Apache-2.0）。
> 本包权重是**转换后的衍生制品**（并含借用的 MTP 头与视觉塔载荷）——
> **改动逐条声明见 `licenses\THIRD_PARTY_NOTICES.md`，分发时必须随附该文件与 `licenses\LICENSE`、`licenses\NOTICE.txt`。**

---

> # ★★★ 先读这一页：这是「起点」，不是「照抄清单」（给接手 agent 的行动原则）
>
> **一、三条硬原则**
> 1. **一切以本机实测为准。** 本文档里的路径、文件名、端口、参数、读数，都是**在我们机器上成立的一组取值**。
>    到了你这台机器：**先测，再定** —— `nvidia-smi --query-gpu=name,compute_cap,driver_version,memory.total`、
>    路径是否纯 ASCII、磁盘余量、Python/torch 有没有。然后据此**自己选**引擎、制品、KV 档、上下文与投机参数。
> 2. **对不上不叫出错。** 架构不同、KV 档在你卡上不可用、显存装不下、路径带中文、驱动太老、缺某个制品 ——
>    这些是**"本机情况"，不是"方案坏了"**。正确动作是**按本机改**（换引擎 / 换档 / 挪路径 / 自己编一份 / 换配置），
>    **不是**把整份方案判死，更不该由"电脑的主人说部署不了"来否决。
> 3. **你有行动权，也有举证义务。** 遇到问题请**先在本机做适配尝试**，再回报；回报必须带三样证据：
>    **① 你用的引擎 sha256 前 16 位 ② 制品文件名 ③ 完整命令 + 日志原行**。
>    **只报"部署不了"而不带这三样，我们无法判断，也不会据此否掉方案。**
>
> **二、常见"不匹配" → 本机自行处置（照这张表做，不用等我们）**
>
> | 本机情况 | 你可能看到 | 自己怎么办 |
> |---|---|---|
> | 显卡架构不同 | 起服卡住（单核 CPU 满载 + GPU 几乎闲置）；或报 `requires compute capability 12.0 or 8.9` | 用**匹配你架构的引擎**；包内没有就用 `src-tree` **自己编一份**（改三处门 + 构建开关，见 `docs\引擎-模型-参数对照表.md` §6） |
> | KV 档被拒 | `kv-dtype 'rk4v4' requires compute capability 8.9` | 按架构换档：**40 系 `rk4v4` / 50 系 `nvfp4` / 两代通用 `fp8`** |
> | 显存不够 | 容量硬检查、报差多少字节 | 降 `--max-context`，或换 4-bit KV；**别照抄我们那组 262144** |
> | 路径带中文 | `invalid UTF-8 byte` / "系统找不到指定的路径" | 把包挪到纯 ASCII 路径（如 `D:\infer\`） |
> | 驱动太老 | `0xC0000135` 或行为异常 | 升级驱动（引擎走驱动侧 CUDA，**不必装 Toolkit**）；或换一台机器 |
> | 缺某个制品 | 启动件报 `[MISSING]` | 用**自制套件**产出（下载上游件 + 一条命令），或先跑不需要它的那一档 |
> | 读数与文档不同 | 我们写 226、你测 244… | **跨卡不可比**：先对齐口径（长提示 / 长输出 / 贪心 / 丢第一次 / 取中位），再看是否落在**带宽比**范围内 |
> | 前缀复用报 500/503 | `candidate token ledger does not match prompt length` | 这是**已知缺陷**（我们修过）：换修好的引擎，或临时加 `--no-prefix-reuse`；判据与三步自查见 `docs\复现手册-排错篇.md` |
>
> **三、什么时候该回来找我们**
> - 你已按上表**适配过**，仍然：**起不来**（带完整 stderr）／**数值或输出异常**（带可比对样例）／
>   **性能显著低于带宽比**（带卡型 + 驱动 + 配置 + 读数）；
> - 或者你**跑通了我们没做过的组合**（别的架构、别的 KV 档、别的路线）—— **那种请把读数发回来，
>   我们补进包并署名来源**。
>
> **四、我们提供什么、不承诺什么（免得来回扯）**
> 我们提供：**一档可跑的最小可用集 + 判据 + 工具链 + 源码树**。
> 我们**不**承诺：跨卡的同读数、你那张卡的阈值最优值、未验架构上的性能。
> 凡我们没验过的，文档里都标了"未验"—— **那些地方以你的实测为准。**

---
## 1. 这是什么 / 适合谁

| 项 | 值 |
|---|---|
| 模型 | Bonsai-2-27B（三元量化 PQ2_0_G128，2.125 bpw） |
| 引擎 | ninfer **dev fork**（v1.0.8 线）`ninfer-serve.exe` |
| 权重 | **7.74 GB**（`bonsai2_27b_ternary_v2.ninfer`，含视觉塔）／**9.81 GB**（`…-dflash2.ninfer`，多一支 DFlash2 草稿分支，见 §4.6） |
| 显存占用 | **8.54 GiB**（纯文本，KV 262,144 token、fp8）／**8.78 GiB**（开视觉）／**DFlash2 档：权重 9.10 GiB**（32K 上下文时全卡约 12.3~12.6 GB） |
| 投机解码 | **默认开**（`--spec mtp --draft-tokens 3`，2026-09-26 起）；另有 DFlash2 档（§4.6），比 MTP 再快 15~25% |
| 上下文 | 池/窗口 262,144 |
| 并发 | **单路**（固定） |
| 端口 | **8084**（纯文本）／**8086**（开视觉） |
| **视觉** | ✅ **本包能力完整**，见 §2.1 |

**适合**：显存 12~16 GB、要**速度**、跑常规对话/短提示任务。
**不适合**：要读 1M 级超长语料（走另一档）；要绝对最高质量（走全精度 27B）。
**多路会掉速**：实测每加一路，单路速度掉约 28%（113.3 → 79.3 → 57.6 t/s）。本档只做单路。

---

## 1.1 ★ 视觉（多模态）：**本包带视觉，且实测可用**

**结论**：**不用另外下任何东西**。视觉塔（333 个对象）**已在本包的权重文件里**，
引擎也**编译了媒体支持**（镜像链入 `avcodec`/`avformat`，这就是包内那 7 个 ffmpeg dll 的用途）。
**唯一的区别只是启动时要加 `--vision`** —— 所以本包给了两个启动件：

| 启动件 | 端口 | 视觉 | 权重 | 运行时 | 用途 |
|---|---|---|---|---|---|
| `start-8084.bat` | 8084 | 关 | 6.70 GiB | **8.54 GiB** | 纯文本，省 0.24 GiB |
| `start-8086.bat` | **8086** | **开** | **6.97 GiB** | **8.78 GiB** | 收图片输入 |

**视觉代价（实测）**：权重 +0.27 GiB、运行时 +0.24 GiB、另有 `media` 子系统
（`16 preprocess workers | cache 1.00 GiB | live 2.00 GiB`）。**想省显存就默认别开。**

### 实测判据（2026-09-26，本包自证）

启动日志（带 `--vision`）：
```
weights ready | 6.97 GiB | 2.1s
capacity | KV 262,144 tokens, fp8, explicit | pages 4,096/4,096 | runtime 8.78 GiB | free 14.9 GiB
media | 16 preprocess workers | cache 1.00 GiB | live 2.00 GiB
listening on http://127.0.0.1:8086
```

**真喂图跑通**（两张不同内容的图，答案可判真伪）：

| 图 | 内容 | 模型回答 | 结果 |
|---|---|---|---|
| `image7.png` | 手写体分数 **1/2** | `\frac{1}{2}` | ✅ 对 |
| `image62.png` | 公式 **μ = 0.2** | `\mu = 0.2` | ✅ 对 |

请求格式（OpenAI 兼容，**注意仍必须带 `model` 字段**）：
```json
{"model":"qwen3.8-27b",
 "messages":[{"role":"user","content":[
   {"type":"text","text":"图里是什么等式？"},
   {"type":"image_url","image_url":{"url":"data:image/png;base64,<...>"}}]}],
 "max_tokens":64,"temperature":0}
```

> ⚠️ **两个坑**：① `--spec dflash` 与 `--vision` **不能同开**（引擎硬报错）；
> ② 视觉会**吃上下文**（一张 384×992 的图 ≈ 374 token 的 prompt），长文档 + 多图要留意 262,144 这个顶。

---

## 1.2 启动件总表（**五个**）★ 先看这张表再动手

| 启动件 | 端口 | 用哪份制品 | 上下文 / KV | 投机 | 适用显存 |
|---|---|---|---|---|---|
| `start-8084.bat` | 8084 | 基础 PQ2 | 262144 / fp8 | **MTP 3（默认开）** | ≥ 16 GB（12G 会拒启） |
| `start-8086.bat` | 8086 | 基础 PQ2 | 262144 / fp8 | 无（视觉档保持原样；"视觉+投机"本包未验） | ≥ 16 GB |
| **`start-8087-12g.bat`** | 8087 | 基础 PQ2 | **131072 / rk4v4** | MTP 3 | **12~16 GB** ← 12G 卡用这个 |
| **`start-8085-dflash2.bat`** | 8085 | **`…-dflash2.ninfer`** | 32768 / fp8 | **DFlash2 K=7** | ≥ 16 GB（权重 9.10 GiB） |
| **`start-8088-dflash2-128k.bat`** | 8088 | **`…-dflash2.ninfer`** | **131072 / fp8** | **DFlash2 K=7** | **≥ 24 GB**（权重 9.10 GiB + fp8 KV ~4.0 GiB）← **大卡首选（最快 + 长上下文）** |

> ★ **KVMem 默认关，但包内自带日志显示它曾开着**：`agent-logs\engine-8197.err.log` 里那些 `host KV pinned` / `kvmem-map publish ok` 行，是我们**带 env 的实测实验**留下的；**出厂默认不设**那三个 env（`NINFER_TERNARY_KVMEM` / `_WINDOW_ASSEMBLY` / `_SEMANTIC`），读到这些行说明有人开过。
>
> ★ **档位更正（2026-09-27，消除矛盾点）**：**DFlash2 K=7 归 16 GB 档** —— 它的启动件 `start-8085-dflash2.bat` 额定就是 **≥16 GB**（权重 9.10 GiB）。上表 `start-8088` 那行的 **≥24 GB 是「128K 上下文变体」的显存口径**（9.10 GiB 权重 + fp8 KV ~4.0 GiB），**不是「用 DFlash2 需要 24 GB」**。下面 🎯 那句里的「≥24 GB」同此更正为 **16 GB 及以上**。

> 🎯 **16 GB 及以上（尤其 50 系）首选 `start-8085-dflash2.bat`（DFlash2 K=7）** —— 志愿者在 RTX 5090 D 上**未重编**实测
> **512.9 t/s**（数数字，接受率 97.9%），比最强 MTP（343.8）**快 49%**；散文 154.7 t/s。**同卡不同内容差 3 倍，报数一定带内容类型 + 接受率**。
> 规律：**吞吐 = 步速 × (1 + K×接受率)**，步速是卡的属性、接受率是内容的属性（详见 `docs\引擎-模型-参数对照表.md` §4.5「破案」）。
> **12G 卡的唯一坑**：默认那个 `start-8084.bat` 要 262144 上下文 + fp8，物理上装不下（起不来时会明确报差多少字节）。
> 这不是配置问题，是 12 GB 的硬顶 ⇒ 用 `start-8087-12g.bat`：KV 换成 **4-bit 档**，
> 每 token 从 32.2 KiB 降到 **17~18 KiB**，128K 只需约 **2.1~2.3 GiB**。
> ⚠️ **但 4-bit 档是分架构的，引擎里是硬门（不是偏好）**：
>
> | KV 档 | 每 token | 40 系（8.9） | 50 系（12.0） | 实测报错原文 |
> |---|---|---|---|---|
> | `rk4v4` / `rk4v4-e8` | 17.0 KiB | ✅ | ❌ | `kv-dtype 'rk4v4' requires compute capability 8.9` |
> | `k8v4` / `nvfp4` | 25.1 / 18.0 KiB | ❌ | ✅ | （50 系专属内核，sm_100+） |
> | `bf16` / `int8` / `fp8` | 64 / 33 / 32.2 KiB | ✅ | ✅ | — |
>
> `start-8087-12g.bat` 会**按卡自动选**（8.9→`rk4v4`／12.0→`nvfp4`）。
> ⚠️ 另有更上一条的总门：**本引擎运行时只接受 cc 8.9 与 12.0**（源码硬门
> `Qwen3.6 family runtime requires compute capability 12.0 or 8.9`）⇒ 30 系 / A100 / H100
> **不是"没实测"，是运行时明确不支持**；要支持得改门 + 补对应档内核。
> ⚠️ 还要分清：**`rk4v4` 是容量档、不是速度档** —— 它的 decode 比 `fp8` 略慢
> （每层每次 attention 多一个 inverse-rotate 内核，字节减半却被这点固定开销吃回去）；
> 它买的是"窗口能从约 120K 开到 262144"。**要速度用 `fp8`，要窗口用 4-bit。**

> ### ⚠️ 引擎必须与你的卡架构匹配（本包最容易"看起来像卡死"的坑）
>
> `engine\` 里现在是**两份引擎**，各自**只认自己的架构**，而且**都不含对方架构的 PTX**：
>
> | 引擎文件 | 架构 | 适用卡 | sha256（前 16 位） |
> |---|---|---|---|
> | `engine\ninfer-serve.exe` | **sm_89** | RTX 40 系 | `566F0D0ED8FF23E0` |
> | `engine\ninfer-serve-sm120.exe` | **sm_120** | RTX 50 系 | `FE170EB23FFDBFF5` |
>
> **五个启动件都会自己按卡选**（读 `nvidia-smi --query-gpu=compute_cap`：`8.9`→sm_89、`12.0`→sm_120；
> 其它架构**直接报错退出**，不会硬跑）。手敲命令时用对的那一份。
>
> **症状对照**：拿 sm_89 引擎在 50 系上跑，**不是"JIT 慢"，而是根本没有可用内核镜像** ——
> 表现是**卡在启动 / CUDA 图捕获阶段、单核 CPU 满载、GPU 几乎闲置**（实测 `566F0D0E`：2 个 sm_89 cubin、
> **PTX 条目 = 0**；sm_120 那份：5 个 sm_120 cubin + 3 条 `*.sm_120a.ptx`）。
> **第一件事永远是核架构**：`nvidia-smi --query-gpu=compute_cap --format=csv`。
> 本档没有 30 系（8.6）/ A100（8.0）/ H100（9.0）的引擎 ⇒ 用对应 kit，或按 `docs\` 里的自编译指引自己编。

---

## 2. 硬件前提

| | 最低 | 推荐 |
|---|---|---|
| 显卡 | NVIDIA，**显存 ≥ 10 GB**（本机实测占用 8.54 GiB + 余量） | RTX 4080 SUPER 级 / ≥ 16 GB |
| 内存 | 16 GB | 32 GB |
| 磁盘 | ≥ 9 GB 空余（放包） | SSD（权重读取 1.3s） |
| 系统 | **Windows x64**（已验证） | — |
| 运行库 | **不需要装 CUDA Toolkit**：引擎用驱动侧 CUDA 运行库（`nvcuda.dll` / `nvcudart_hybrid64.dll`）。已实测：PATH 只有 CUDA 12.8 也能起到 `listening` | 仅需较新 NVIDIA 驱动 |

> ⚠️ **本包只在 RTX 4080 SUPER（32,760 MiB）上验证过**。别的卡能跑，但**读数会不同**，
> 跨卡数字**不可比**（显存带宽、SM 数、能不能跑 CUDA Graph 都影响）。

---

## 3. 怎么跑（三步）

### 3.1 起服务
```
双击 start-8084.bat        （≥16 GB 显存；上下文 262144 + fp8 + MTP3）
双击 start-8087-12g.bat    （12~16 GB 显存；131072 + rk4v4 + MTP3）
双击 start-8085-dflash2.bat（≥16 GB；DFlash2 K=7，需 -dflash2 制品）
```
（**无需安装 CUDA Toolkit**。仅当引擎报 `0xC0000135` 时，才需要设置 `CUDA_BIN`。）
**投机解码自 2026-09-26 起默认开启**（`--spec mtp --draft-tokens 3`）：实测它把 decode 提高 40%~3.4×
（幅度取决于内容可预测性），代价是 0.42 GiB 权重。想对比关掉的效果就自己删掉那三个参数。

### 3.2 判就绪
```powershell
curl.exe -s -o NUL -w "%{http_code}" http://127.0.0.1:8084/v1/models
```
期望 **`200`**（本机冷启动到 200 约 **4~6 秒**）。详见 `判据.txt`。

### 3.3 发第一个请求
⚠️ **ninfer 与 llama.cpp 不同：请求体必须带 `model` 字段。**
```powershell
curl.exe -s http://127.0.0.1:8084/v1/chat/completions `
  -H "Content-Type: application/json" `
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"你好"}],"max_tokens":64}'
```

---

## 4. 实测读数（**必须连着口径看**）

**口径**：RTX 4080 SUPER 32,760 MiB ／ 单路 ／ 本包内的引擎与权重（SHA256 见 `SHA256SUMS.txt`）

| 指标 | 读数 | 口径 |
|---|---|---|
| **prefill** | **2,230 t/s** | 4,070-token 提示、`max_tokens=8`、每次换随机 nonce 强制冷缓存；TTFT 1.9 s |
| **decode** | **226.0 t/s** | ctx 16384、贪心、400 token、1 warmup + 3 跑取中位；接受率 81.75%（5.48 tok/round） |
| 权重加载 | 6.70 GiB / 1.3 s | 启动日志 |
| 端到端就绪 | 4.0 s | 启动日志 `engine ready` |

> **口径差异（别拿错数）**：工作室配方文档里的同档旧读数是 prefill **1,980 t/s** / decode **≈210 t/s**，
> 那是**更早的二进制**测的；本包引擎是 2026-09-25 15:03 构建的版本，
> 同一台机器上新测为 2,230 / 226.0。**同卡同参数下量级一致**即可，绝对值不要跨版本、跨卡比较。

---

## 4.5 这个包**验过什么**（自证记录，2026-09-26）

**验收方式**：不是"手敲命令能跑"，而是**用交付入口本身**（`start-8084.bat`）从**包内**起服务，
模型与引擎路径**全部指向包内件**（**没有任何包外依赖** —— 不依赖我们内部目录、不依赖任何下载）。

| 验收项 | 结果 |
|---|---|
| `GET /v1/models` | **HTTP 200**（冷启动到就绪 **4.4 s / 5.1 s**，两次） |
| 返回体 | `{"id":"qwen3.8-27b","max_model_len":262144,"owned_by":"ninfer"}` |
| 一次真推理 | ✅ 返回正确（`prompt=18 / completion=16`），**无 500、无 FATAL** |
| 引擎启动日志 | `weights ready 6.70 GiB / 1.3s` → `capacity KV 262,144 tokens, fp8, explicit \| pages 4,096/4,096 \| runtime 8.54 GiB \| free 15.4 GiB` → `listening on http://127.0.0.1:8084` |
| GPU 占用 | 16,462 MiB（运行中；停后回落 659 MiB，**无残留进程**） |
| 引擎 SHA256 | 与冻结源 `b1\apps\ninfer-serve.exe` **逐位一致** |

### ⚠️ 打包过程中踩过、已修的两个坑（**接手人别再踩**）

1. **`start-8084.bat` 不能写中文**。我第一版是 UTF-8 + `chcp 65001`，结果 cmd 按 ANSI 码页解析
   **把批处理命令本身撕碎**（报 `'（或' is not recognized`），**引擎根本没起来**，而报错完全指不到真因。
   ⇒ 本 bat 是**纯 ASCII、无 BOM**（已验字节）。中文说明一律放 `判据.txt`；改这个 bat 时**别加中文**。
2. **CUDA 运行库在 `bin\x64\`，不在 `bin\`**。本机 CUDA 的 `bin\` 里只有工具（`nvcc`/`ptxas`…），
   运行库 `cudart64_13.dll` / `cublas64_13.dll` / `cublasLt64_13.dll` 等 6 个在 `bin\x64\`。
   自检若只探 `bin\` 会**误报"缺 cudart"**（引擎其实起得来）。⇒ bat 里已改为**两个位置都探**。

> **为什么把坑写进交付件**：这两条都会让接手人**误判"包是坏的"**，而实际包没问题——
> 自检误报比没有自检更坏 —— 我们的内部坑表里专门为它立了两条（§5.62 / §5.63），都在本档 `docs\复现手册-排错篇.md` 里有对应条目。

---

## 4.6 ★ DFlash2 档（2026-09-26 新增）—— 比 MTP 再快 15~25%

**它需要第二份制品**：`model\bonsai2_27b_ternary_v2-dflash2.ninfer`（**9.81 GB**）。
它 = 本包原来的 PQ2 制品 **+ 66 个 `dflash2/*` 对象**（2.07 GiB：`feature_projection`、`context_norm`、
5 层的 context KV/attention/mlp、两个 248320×256 的候选码本等）；
**原有 1126 个对象逐字节照搬，一个字节都没改**。启动件：`start-8085-dflash2.bat`（端口 8085）。

**★★ 唯一必须记住的一条**：命令里必须带 **`--lm-head-draft`**（启动件已经带了）。不带就死在启动阶段：

```
ERROR startup failed | preparing CUDA graphs | 1.4s
FATAL server failed during startup | linear_topk: unsupported head profile
```

原因：DFlash2 的提案步要一个"融合 top-k"内核，而它只认三种档 —— `W8 @248320 行` / `FP8 @248320 行` /
`Q4 @131072 行`。本制品的 `text/output_head` 是 **PQ2（三元）**，不在其中 ⇒ 走包内自带的那个
131072 行 Q4 草稿头（= `--lm-head-draft`）。**这不是引擎缺功能，是那个矩阵的格式决定走哪条路。**

**实测（本机 4080S 级 / 贪心 / 单路 / 600 token 输出；口径必须连着看）**

| 负载 | 不投机 | MTP d4 | DFlash2 K=5 | DFlash2 K=7 |
|---|---|---|---|---|
| 数数字（高可预测） | 63.7 | 211.9（接受 95.0%） | 279.6（99.2%） | **353.8**（97.9%） |
| HTML+SVG（结构化） | 62.9 | 172.0（78.0%） | **205.3**（71.8%） | 193.9（48.1%） |
| 散文（自由生成） | 62.4 | 88.2（26.2%） | 108.6（27.6%） | **112.1**（21.2%） |

- **K 怎么选**：结构化内容（HTML/代码）用 **K=5**；高度可预测（格式化输出、数数字）用 **K=7**；
  散文 K=5 与 K=7 基本持平。**K 不是越大越好**（K=9 时散文掉到 62 t/s，比 MTP 还差）。
- **K≤7 是工程上界，不是引擎上界**：引擎硬校验允许 `mtp` **1..5**、`dflash`/`dflash2` **1..15**（源码 `src\product\speculative_options.h`）—— 但验证宽度 `T=K+1` 一旦 >8 就掉出小批档，单轮成本从约 13 ms 跳到约 40 ms
  （我们实测 K=7 **351** → K=8 248 → K=9 276 的断崖就是这个原因）。
- **质量**：20 题闸门（xhigh / 32768 预算 / 4 路）**19/20**，唯一错题 `MMLU-Pro:law`
  与历史最好臂错的**同一题**（历史 `--lm-head-draft` 臂是 18/20）。
- **显存**：DFlash2 档**权重 9.10 GiB**（MTP 档 7.12、不投机 6.70）⇒ 32K 上下文时全卡约 **12.3~12.6 GB**，
  262144 上下文时约 **19.5 GB**。**12 GB 卡会很紧**（本包没给 12G 的 DFlash2 启动件）。
- **副作用（如实说）**：`--lm-head-draft` 会让同样的题**多生成约 85% token**（20 题闸门 41,672 → 77,079）
  ⇒ **t/s 高 ≠ 墙钟快**（该臂每 token 快 62%，墙钟只打平）。**"极速"这个词只在同口径下成立。**

---

## 5. 目录结构与校验

```
models\PQ2\                         （与 models\PTQ1\ 同构）
├─ engine\        ninfer-serve.exe + 7 个 ffmpeg dll（缺一不可，必须同目录）
├─ model\         bonsai2_27b_ternary_v2.ninfer        (7.74 GB，基础档)
│               bonsai2_27b_ternary_v2-dflash2.ninfer (9.81 GB，+DFlash2 草稿分支，见 §4.6)
├─ docs\        复现手册 / 排错篇 / 性能附录 / 交付件清单（**本档自带全套**）
│               ★ 线上对照-50系与30系适配现状（**别人做到哪一步**）
│               ★ 调参与扫参-速度怎么来的（**"我这很慢"看这份**）
│               ★ 调参-按卡重拟合int8档起点-自改配方（**老卡/中低端卡 prefill 提速：改一行 + 重编**）
│               ★ 引擎-模型-参数对照表（**该用哪份引擎/哪个模型/哪些参数 —— 照表抄，别猜**）
│               ★ 适配案例集 / ★ 构建与ABI校验-SOP / ★ 源码导读（构建·换卡能力三件套）
├─ licenses\      ★ 许可证与改动声明（**分发时必须整目录随附**）
│   ├─ LICENSE              官方 Apache-2.0（Prism 仓库原样取回，未改一字）
│   ├─ NOTICE.txt           官方版权声明（含要你照抄的署名句）
│   ├─ THIRD_PARTY_NOTICES.md  ★ 本包制作方书写的**改动声明**（含视觉塔下载指引）
│   └─ KNOWN_ISSUES.md      官方已知问题（已扫，无使用限制条款）
├─ start-8084.bat 起服务·纯文本（含 CUDA PATH 设置）★纯 ASCII
├─ start-8086.bat 起服务·开视觉（同一个引擎与权重，仅多 --vision）★纯 ASCII
├─ 判据.txt       就绪判据 / 期望日志 / 常见故障处置 / 边界
├─ README.md      本文件
└─ SHA256SUMS.txt 校验和（引擎 + 7 dll + 权重 + 全部文档；不含自身）
```

**校验**：
```powershell
Get-FileHash .\engine\ninfer-serve.exe -Algorithm SHA256
# 期望 566F0D0ED8FF23E0FDBFD66E8B5C8C704228F883E728923E87565766FB2BACB8
Get-FileHash .\model\bonsai2_27b_ternary_v2.ninfer -Algorithm SHA256
# 期望 05BBBF01090C6F61113B54556DAA22AD0B45036A078AF6CD6F02A3FDE47AD76C
Get-FileHash .\model\bonsai2_27b_ternary_v2-dflash2.ninfer -Algorithm SHA256
# 期望 F66C8300EFF996A58893E7D567A3E000D7B6347F3A72B2124EAC11791720E148
```
**为什么要校验**：包是从**实验目录的冻结副本**做出来的（实验目录会被后续实验覆盖），
SHA256 是"你手上这份 = 我们测过那份"的唯一凭据。

---

## 6. 边界与未验（**先说清楚做不到什么**）

| 项 | 状态 |
|---|---|
| 引擎来源 | **dev fork**，不是生产引擎（**生产引擎二进制里没有三元量化支持**）。这是**有意为之**，如实标注，未做生产化。 |
| **KVMem（长上下文）技术** | **引擎里继承了它，但【默认关闭】**（⚠️ 包内 `agent-logs\engine-8197.err.log` 里出现过 KVMem 的行 —— 那是我们**带 env 的实验日志**，不是出厂默认） —— 总开关 `NINFER_TERNARY_KVMEM`（连同 `_WINDOW_ASSEMBLY` / `_SEMANTIC`）**只在 `=1` 时生效**；**默认档与出厂逐位一致，别去开**（详见 `docs\引擎-模型-参数对照表.md` §6.5）。 |
| `--disk-cache` | **不支持**。v1.0.8 线没有这个参数，加了引擎起不来（报 `unknown argument`）。 |
| 路径 | **必须纯 ASCII**。中文/非 ASCII 路径会导致 `[json.exception.type_error.316] invalid UTF-8`。 |
| `--kv-capacity` | **必须 ≥ `--max-context`**（引擎硬检查，违反即拒启）。 |
| 超长上下文 | 本档**不是**超长方案。要读 1M 级语料请走**成品 P001**（纯 llama + KVMem 三元线，另档交付）。 |
| 多卡 / 非 40 系 / Linux | **未验**。 |
| 并发 | 固定单路；加路会掉速，未做多路调优。 |
| **投机输出的口径** | **投机 ≠ 逐字无损**：实测"开投机"与"不开投机"的贪心输出**不逐字相同**——高置信任务（数数字）逐字一致，开放任务（散文/HTML）在很早就分叉。原因是贪心近似并列时的数值翻转还是验证规则有损，**我们没定性**；因此本包只声明"速度 ×N"，**不声明"文本等价/无损"**。 |
| **`--lm-head-draft` 的代价** | 它让同样的题多生成约 85% token（20 题闸门 41,672 → 77,079）⇒ 每 token 快 62% 但**墙钟只打平**。 |
| **`--draft-tokens` 的边界** | **引擎允许 1..15**（`dflash`/`dflash2`）/ **1..5**（`mtp`）；**工程甜点 5/7** —— K=8 起验证宽度越过小批档，单轮成本从约 13 ms 跳到约 40 ms（实测 K=7 351 → K=8 248 → K=9 276）。 |
| **`rk4v4` 的定位** | **容量档，不是速度档**：4-bit KV 把每 token 从 32.2 KiB 降到 17.0 KiB（192K 窗口成为可能），但 decode 比 `fp8` 略慢。 |
| **`--wddm-evictable-budget`** | 社区在 12G 卡上实测会卡死初始化，我们这边**没有结论** ⇒ **别加**。 |
| 视觉塔独立件 | **本包不需要它**（视觉塔载荷已在权重文件内，且实测可用）。官方另发独立件 `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`（629,246,976 B，SHA256 `6807EDE6…1903`）**仅供**"自己从零复现 / 换引擎路线"时使用 ⇒ 指引见 `licenses\THIRD_PARTY_NOTICES.md` §4。 |
| 权重性质 | **转换后的衍生制品**（非官方原件）：重新编码 + 借用了 MTP 头与视觉塔载荷。**改动逐条声明见 `licenses\THIRD_PARTY_NOTICES.md` §2**。SHA256 与官方 `.gguf` **必然不同**，别互相核对。 |

---

## 7. 出处与许可

**上游（Apache-2.0，两层）**
- **Bonsai 2 27B** © 2026-present Prism ML, Inc. — `https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf`
- **Qwen3.8-27B**（基座，也是本包 MTP 头的来源）© 2026 Alibaba Cloud — `https://huggingface.co/Qwen/Qwen3.8-27B`
- 署名（官方请求原句）：**"Created using Bonsai by Prism ML."**
- 本包改动声明与你的分发义务：`licenses\THIRD_PARTY_NOTICES.md`

**本包制作出处**
- 打包器与改动证据：**制品的打包含有逐张量映射规格与对账脚本**（含 `MAPPING.json`、字节级往返证明）—— 这些是我们的制作内部件，未随本档分发



---

## ★ 源码树完整性校验（分发前/后都跑一次）

`SHA256SUMS.txt` 覆盖 docs / engine / model / 顶层脚本；**源码树另有独立清单**（src-tree 有上千文件，单独校验更快）：

```powershell
# Windows（在包根目录执行）
Get-Content src-tree-MANIFEST.sha256 | ForEach-Object {
  $h,$p = $_ -split '\s+',2
  if((Get-FileHash (Join-Path 'src-tree\<树目录>' $p) -Algorithm SHA256).Hash.ToLower() -ne $h){ "FAIL $p" }
}
```

```bash
# Linux / macOS（在 src-tree 目录内执行）
sha256sum -c ../src-tree-MANIFEST.sha256 | grep -v ': OK$'   # 无输出 = 全部通过
```

> 传输丢件最常见的形态：**文件数少于清单条数**。先数文件，再比哈希。
> 本包 `src-tree` 的基准文件数已写在 `src-tree-MANIFEST.sha256` 的条目数里。