# THIRD-PARTY NOTICES ｜ 第三方声明与改动说明

**本目录属于**：三元 Bonsai-2-27B on ninfer 交付包（档 PQ2）
**本文件性质**：本包**制作方**（非 Prism ML、非阿里云）书写的**改动声明与署名**。
**日期**：2026-09-26

> 本包内的模型权重**不是**官方原始文件，而是**转换后的衍生制品**。按 Apache-2.0 §4(b)，
> 我们必须显著声明改动。原文见 `licenses\NOTICE.txt`（官方件，未改一字）。

---

## 1. 上游是谁 / 许可证是什么

本包权重有**两个上游**，**两层都是 Apache-2.0**：

| 上游 | 版权 | 许可证 | 官方地址 |
|---|---|---|---|
| **Bonsai 2 27B**（三元权重与模型结构） | Copyright 2026-present **Prism ML, Inc.** | **Apache-2.0** | `https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf` |
| **Qwen3.8-27B**（基座；也是本包 **MTP 头**的来源） | Copyright 2026 **Alibaba Cloud** | **Apache-2.0** | `https://huggingface.co/Qwen/Qwen3.8-27B` |

官方 `NOTICE.txt` 逐字原文（**请照此署名**）：

> This software is copyright 2026-present Prism ML, Inc. It is available under the Apache 2.0 license.
> If you publicly deploy or redistribute this software, we would appreciate attribution such as:
> **"Created using Bonsai by Prism ML."**
>
> This software is built from Qwen3.8-27B, Copyright 2026 Alibaba Cloud, which is available under
> the Apache 2.0 License: https://huggingface.co/Qwen/Qwen3.8-27B/blob/main/LICENSE

**建议署名（中英皆可，取其一或并列）**：

```
Created using Bonsai by Prism ML.
Built on Qwen3.8-27B (Copyright 2026 Alibaba Cloud, Apache-2.0).
Repacked to the ninfer format by <本包制作方>; modifications disclosed below.
```

---

## 2. ★ 本包对权重做了什么改动（**逐条，不省略**）

本包内的 `bonsai2_27b_ternary_v2.ninfer` **不是**官方 `.gguf` 的改名或容器封装，
而是**重新编码 + 拼装**的产物。改动共四类：

| # | 改动 | 说明 | 是否改变数值 |
|---|---|---|---|
| **1** | **容器与编码转换** | 官方 `Ternary-Bonsai-2-27B-PQ2_0.gguf` → ninfer `.ninfer` 制品格式 | 三元权重按 Prism 两种三元类型重新组装**平面**（`PQ2_0_G128`）；有**逐字节往返证明**（拆解回原文与源 GGUF 逐字节相等） |
| **2** | **部分张量做了格式变换** | 每个 matmul 的 norm / scale 等按 ninfer 侧约定变换（如 `output_norm.weight - 1.0`、SSM 的 `alpha/beta` 由 tiled 转 grouped、`dt.bias` 取对数等） | **是**，属确定性变换，规则与证据记录在制作方 `MAPPING.json` |
| **3** | **借用 MTP 头（12 个张量）** | Bonsai 的 GGUF **没有** MTP 头（851 张量、无 `blk.64.*`）。本包**加入了 MTP**：从**官方 Qwen3.8-27B 的 MTP 头**取 12 个张量补齐 | **是**，属**外来组件**。制作方核对：12 个张量与模板余弦 **≥ 0.99966**，其中 7 个 norm **逐位相同** |
| **4** | **借用视觉塔（333 个对象）与前端（6 个）** | 视觉塔在官方是**独立文件** `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`；本包内含的是**同一套官方视觉塔**的载荷。前端 = 分词器等 | 视觉塔**不参与文本解码**；前端来自同源模板 |

**其他制作细节**（供审查者复算）：

- 三元载荷是**原样搬运**的（`ternary_bytes_verbatim`），不为追求体积而重训或再量化；
- 打包器源码 `pack.py` 的 docstring **自行声明**了上述借用清单，原文：
  `borrowed payloads ... {'frontend': 6, 'text': 2, 'mtp': 12, 'vision': 333}`
- 制作方**已知并修复过**一个自身缺陷：首次打包时行置换 `perm48()` 不是双射，导致 6144 行里丢 4064 行、
  且**所有体积/行数/字节校验全部照常通过**（症状是"通顺的胡话"）。已由 `perm_row()` 修复，
  现制品校验通过（6144/6144 行互异、0 重复、0 缺失）。**此处如实披露，因为它说明"体积对得上"不等于"内容对得上"。**

---

## 3. 本包**不含**什么

- **不含**官方原始 `.gguf` 文件本体（那是另一份制品，SHA256 与 `.ninfer` 必然不同，别互相核对）；
- **不含**视觉塔的**独立文件**（本包已含其载荷，但若你要自己搭别的路线，请另下独立件，见 §4）；
- **不含**任何训练/微调产物：本包**未对 Bonsai 或 Qwen 做微调或再训练**。

---

## 4. 视觉塔：独立下载指引

官方把视觉塔**单独发**（不塞进语言模型）。**本包的语言模型已含其载荷**，但如果你要：
自己从零复现、或搭别的引擎路线、或单独替换视觉塔 —— 请下这一件：

| 项 | 值 |
|---|---|
| 文件名 | **`Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`** |
| 体积 | **629,246,976 B**（0.59 GB） |
| SHA256 | `6807EDE61D570BB86BA34B756A0FA109EDC33668604DE867C6EA6D8F1D631903` |
| 官方地址 | `https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` |
| 备选（更高精度） | `Ternary-Bonsai-2-27B-mmproj-BF16.gguf` = 931,145,856 B（0.87 GB） |

> 本包制作方手上的这一件，与官方公布体积**逐字节相同**（即官方原件），上表 SHA256 实测自该件。

**语言模型原件**（若你想从源头自己转换，而不是用本包的 `.ninfer`）：

| 制品 | 体积 | SHA256（本包制作方实测） |
|---|---|---|
| `Ternary-Bonsai-2-27B-PQ2_0.gguf`（**本包对应的官方原件**） | 7,206,168,928 B | `3907DC1658DB1F78A9826BF8D5BCB8DC65DB0D466388937AF57F2294FAE62EC1` |
| `Ternary-Bonsai-2-27B-PTQ1_0.gguf`（均衡档用） | 5,946,648,928 B | `53107F530AA52EB00912263AB1EE29BD199261C87CD7B4AD4CA1318C1FE33EE3` |

> ⚠️ 官方页面公布的体积用的是 GB（十进制口径）：PQ2_0 记 7.21 GB、PTQ1_0 记 5.95 GB；
> 上表是本包制作方实测的**字节数**。两者不冲突，但**别把口径混着比**。

---

## 4.5 ★ DFlash2 草稿分支（2026-09-26 新增，**只存在于 `…-dflash2.ninfer` 这一份里**）

本包自 2026-09-26 起**多带一份制品** `model\bonsai2_27b_ternary_v2-dflash2.ninfer`（9.81 GB）。
它 = 上面那份 PQ2 制品 **+ 66 个 `dflash2/*` 对象**（2.07 GiB）。**第三上游**如下：

| 项 | 值 |
|---|---|
| 来源 | **`z-lab/Qwen3.8-27B-DFlash2`**（Hugging Face） |
| 锁定 revision | `50307d4c4cde6860d4eee73e2547cd786fe8e8a4` |
| 许可 | **Apache-2.0**（模型卡 front-matter 原文 `license: apache-2.0`） |
| 基座 | `Qwen/Qwen3.8-27B`（Copyright 2026 Alibaba Cloud, Apache-2.0） |
| 上游自述 | 该仓库自述为 `incoai/Qwen3.8-27B-DFlash2` 的衍生物 |
| 只取了两个文件 | `config.json`（1,239 B, sha256 `873e3556509b0da06e29654ba00d4944888d4b5e8a33afde25f7eb27d321e980`）与 `model.safetensors`（3,848,817,896 B, sha256 `67fc76d68dc5a9415511a4f394ef744d67510cd20e93b37cc2cc7d28e4bab65c`） |

**制作方对这批载荷做了什么（改动声明）**：

| # | 改动 | 说明 | 是否改变数值 |
|---|---|---|---|
| 1 | **容器与布局转换** | 上游 `safetensors` → 本制品的 `.ninfer` 对象（`BF16/contiguous-le-v1` 与 `W8G32_F16S/row-split-k128-v1`） | **是**，确定性变换 |
| 2 | **量化到 W8/BF16** | `attention/query_key_value`、`attention/output`、`mlp/gate_up`、`mlp/down`、`feature_projection` 按 W8（8 位 + 每 32 权重一个 16 位 scale）重新量化；norm、conv 核、codebook 保持 BF16 | **是** |
| 3 | **张量合并** | `attention/query_key_value` 与 `mlp/gate_up` 由上游的分立 q/k/v、gate/up 合并成一个张量 | **是**（仅排布） |
| 4 | **未做** | **没有**训练/微调/蒸馏；没有改动词表、模板与目标模型权重 | — |

**与原制品的关系（可复算）**：`…-dflash2.ninfer` 里**原有 1126 个对象与本包第一份制品逐字节相同**，
只在末尾追加这 66 个对象；两个文件的 sha256 见 `SHA256SUMS.txt`。
> 制作方还提供了一份**自查工具**（在给外部复现者的补丁包里）：`inject_dflash2.py` + `verify_dflash2.py` +
> 66 对象基准清单 —— 任何人可用它从**官方 GGUF 原件 + 上游 dflash2 原件**重造出**逐字节相同**的这份制品。

---

## 5. 你的义务（照抄即可）

1. **随附**本目录的 `LICENSE` 与官方 `NOTICE.txt`（Apache-2.0 §4(a)(d) 要求）；
2. **保留**本文件（改动声明，Apache-2.0 §4(b) 要求）；
3. **署名**：用 §1 给的那句话；
4. 你若**再改**权重，请在你自己那份里继续声明改动（Apache-2.0 §4(b) 对下游同样适用）。

*本文件由本包制作方书写，不代表 Prism ML 或阿里云的陈述。*


---

## FFmpeg（**2026-09-26 由 GPLv3 构建替换为 LGPLv3 构建**）

| 项 | 值 |
|---|---|
| 随包文件 | `engine\avcodec-63.dll`、`avdevice-63.dll`、`avfilter-12.dll`、`avformat-63.dll`、`avutil-61.dll`、`swresample-7.dll`、`swscale-10.dll`；`src-tree\ninfer-4090w-ternary\ffmpeg\`（bin + include + lib 开发包） |
| 许可 | **LGPL version 3 or later** |
| 版本 | `FFmpeg version n9.0.2-8-gb135b25c19-20260925`（上游 tag n9.0.2 / commit b135b25c19） |
| 构建来源 | BtbN/FFmpeg-Builds（`ffmpeg-n9.0-latest-win64-lgpl-shared-9.0`） |
| 许可全文 | `licenses\FFmpeg-LGPLv3.txt`、`licenses\GPL-3.0.txt`（LGPLv3 引用 GPLv3，须同附） |
| 详细说明 | `licenses\FFmpeg-来源与许可.md` |

> 替换原因：原 GPLv3 构建（`--enable-gpl --enable-version3`）的再分发需随包提供对应源码或书面要约。
> 替换前做了 ABI 校验：引擎对这 4 个 DLL 的 34 个导入符号在新 DLL 导出表中**全部命中**。