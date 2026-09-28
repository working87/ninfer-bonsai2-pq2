# AGENT.md -- machine interface for this package

tier `极速档（ninfer）` | generated 2026-09-26 | machine copy: `agent/manifest.json` (same facts, parseable)
> ## ★★ READ THIS FIRST: 「我们的想法不一定全面」条款（冲突裁决与证否优先）
>
> **我们的文档不是权威，你的当机实测才是。** 凡我们没标出处的内容，一律视为**假设**，不是结论。
> 顺序是：**证否优先 → 实测裁决 → 回执沉淀**（不是"以实测为准"这么一句，那样证否那一步容易被跳过）。
>
> 1. **先证否**：遇到我们解释不了的问题或矛盾点，**第一步是把我们的结论当假设去设计能推翻它的最小实验**，
>    用**你自己机器上的实测数据**判断（不要靠引用我们的文档来论证）。
> 2. **实测裁决**：若证否成立、或这个矛盾我们确实解释不了 ⇒ **以当机实测 + 你自己的判断为准**，不必迁就我们的说法。
> 3. **回执沉淀**：请把回执给我们 —— **矛盾点 + 你的实测证据（命令 + 读数 + 引擎/制品 sha256）+ 你的结论**
>    ⇒ 我们据此改文档、改默认值，并**署名来源**。
> 4. **我们没量过的卡/配置**：不要拿我们的表当答案，用 `gpu-probe.exe` 与最小 A/B 自己量；量不出来就标 `pending`，**不要编数**。
> 5. **判"不改"也要证据**：说"这条对我们没用"时，请给出**同口径的读数**（否则我们会当成噪声/没跑起来）。
>
> **必做项（不读文档也躲不掉）**：包根 **`MUST-DO.md`**（一屏，含「按你的卡看这里」表）＋ 机器可读 **`agent\must-do.json`**。
> 每条带 `evidence_level`：`measured` 我们自己实测 / `author` 原作者数据 / `hypothesis` 猜想未量化 / `pending` 待实测。
> `agent\ninfer-agent.ps1 doctor`（或 `plan`/`start`/`bench`）每次都会带回这份清单的摘要；`must-do` 打印全表，`must-do -Json` 给机器。
> **卡的真实 SM 数**用包根 `gpu-probe.exe` 读（`nvidia-smi` 不报 SM 数）；表只作参考。

**This package is built for an AGENT to drive.** The `.bat` files are a fallback and they are agent-safe now:
`NINFER_AGENT=1` suppresses every pause and turns a needed prompt into a hard error (exit 6);
`NINFER_AGENT_CC=8.9|12.0` removes card detection entirely. The supported interface is
`agent/ninfer-agent.ps1`: no prompts, JSON on stdout, distinct exit codes.

## 1. Drive it in five calls
```
powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 doctor
powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 plan   -Artifact auto
powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 start  -Artifact auto -Port 8096
powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 bench  -Port 8096 -Kind code -Runs 3
powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 stop   -Port 8096
```
Exit codes: 0=ok, 2=bad usage, 3=artifact missing, 4=no engine matches this card, 5=context does not fit in VRAM, 6=engine did not become ready (or, in agent mode, a prompt was needed), 7=not running, 8=request failed, 9=nvidia-smi unusable

## 2. What is here (hashes are the truth)

| file | role | bytes | sha256 |
|---|---|---|---|
| `engine/ninfer-serve.exe` | engine sm_89 (RTX 40 series (Ada, compute capability 8.9)) | 264173568 | `566F0D0ED8FF23E0FDBFD66E8B5C8C704228F883E728923E87565766FB2BACB8` |
| `engine/ninfer-serve-sm120.exe` | engine sm_120a (RTX 50 series (Blackwell, compute capability 12.0)) | 198689792 | `FE170EB23FFDBFF5EB9F9D70A390EC639910BEAB420F30DCB937AF2CD0269C42` |
| `model/bonsai2_27b_ternary_v2.ninfer` | artifact base | 8306927628 | `05BBBF01090C6F61113B54556DAA22AD0B45036A078AF6CD6F02A3FDE47AD76C` |
| `model/bonsai2_27b_ternary_v2-dflash2.ninfer` | artifact dflash2 | 10533733120 | `F66C8300EFF996A58893E7D567A3E000D7B6347F3A72B2124EAC11791720E148` |

## 3. Configuration from measured facts, not taste

| VRAM at least | artifact | spec | K | ctx | KV | lm-head-draft | note |
|---|---|---|---|---|---|---|---|
| 30000 MiB | dflash2 | dflash2 | 7 | 131072 | fp8 | True | best measured configuration on a 32 GB 50-series card: 512.9 t/s on highly predictable content, 154.7 t/s on prose |
| 20000 MiB | dflash2 | dflash2 | 7 | 131072 | fp8 | True | dflash2 artifact file is 10,533,733,120 B = 9.81 GiB (the "9.10 GiB" quoted elsewhere is the weight-only figure); 131072 needs about 4 GiB of fp8 KV |
| 15000 MiB | dflash2 | dflash2 | 5 | 32768 | fp8 | True | 16 GB cards: keep ctx at 32768 and use K=5 |
| 0 MiB | base | mtp | 3 | 16384 | fp8 | False | small cards: MTP drafts 3 tokens; 4-bit KV (rk4v4 on 8.9, nvfp4 on 12.0) halves the KV term when ctx must grow |

## 4. Fault routing (each of these has already been diagnosed once)

| symptom | cause | action |
|---|---|---|
| exits immediately, prints nothing | engine arch does not match the card (sm_89 on a 50-series card or sm_120 on a 40-series card), or the 7 ffmpeg dlls are missing next to the exe | run doctor; start with the engine whose arch matches the reported compute capability; keep exe and dlls together |
| one CPU core near 95 percent, GPU idle, no output | same arch mismatch: the engine spins instead of failing cleanly | kill it, run doctor, use the matching engine |
| FATAL server failed during startup | capacity | the requested context does not fit in VRAM | lower --max-context, or use a 4-bit KV dtype (rk4v4 on 8.9, nvfp4 on 12.0) |
| linear_topk: unsupported head profile | a dflash2 artifact was started without --lm-head-draft | add --lm-head-draft (mandatory for dflash2) |
| kv-dtype 'rk4v4' requires compute capability 8.9 | Ada-only KV dtype requested on a Blackwell card | use fp8 (both arches) or nvfp4 (12.0 only) |
| candidate token ledger does not match prompt length, then 503 inference engine is unavailable | old engine binary: the prefix-reuse ledger guard is wrong and only fires on the SECOND request reusing the same prefix | use the engine in this package (fixed builds reproduce 200/200/200 where the old build gave 200/500/503) |
| Option noheader is not recognized, and the card is then called unsupported | old launcher: --format=csv,noheader inside for /f is split into two arguments | use this package launchers, or run the launcher self-check |
| a stray file appears next to the launcher (for example about or 128K) | banner echo contained an unescaped > which cmd treated as redirection | use this package launchers, or run the launcher self-check |
| . was unexpected at this time, launcher stops | an unescaped ) in an echo line inside an if-block closes the block early | use this package launchers, or run the launcher self-check |
| FATAL ... [json.exception.type_error.316] invalid UTF-8 byte 0xBC, or a CreateFileW that shows question marks where your path has CJK | a path handed to the engine contains non-ASCII characters. The model path cannot be opened at all; a --request-log-jsonl path crashes the JSON writer because those bytes are GBK, not UTF-8. Measured twice on 2026-09-26 | keep the whole package on an ASCII path (any drive and folder name, as long as no CJK appears anywhere above it); the agent CLI already forces its own logs into %TEMP%\ninfer-agent-logs and refuses a non-ASCII artifact path with exit 5 |
| bench shows a low first run and normal later runs (for example 62 then 212 t/s) | the first request after a cold start runs while the GPU clocks are still ramping | discard the first run and take the median of at least three; the agent CLI reports every run so the pattern is visible |
| engine path not found, the launcher reports no such command | the executable is ninfer-serve.exe (with the n), not infer-serve.exe | run the launcher self-check, which now compares every ENGINE= path against the real files in engine\ |
| two arms that should differ return the same number | most often the arm never ran (env not applied, wrong binary, value ignored) | prove the arm with the rung probe before believing a tie |

## 5. Switches (the rebuild column says how the value can be changed)

| name | default | rebuild needed | effect |
|---|---|---|---|
| `NINFER_AGENT_CC` | (unset) | no | forces the card family in every start-*.bat (8.9 or 12.0) and removes the interactive prompt entirely |
| `NINFER_AGENT` | (unset) | no | set to 1: the .bat files stop on nothing (no pause; a needed prompt becomes a hard error, exit 6) |
| `NINFER_TERNARY_S8_MIN_TOKENS` | 33 | no | int8 rung admission threshold. The crossing point is a property of the CARD (66-SM Ada about 17; 76-SM Ada about 32-40), so it must be measured per card. Same-binary A/B. |
| `NINFER_TERNARY_WIDE_MIN_TOKENS` | 41 | no | wide-tile (bf16 mma) admission threshold; same-binary A/B |
| `NINFER_TERNARY_S8` | on | no | 0 disables the whole int8 rung (changes numerics; A/B only) |
| `NINFER_TERNARY_S8_DEBUG` | off | no | 1 prints one stderr line per ternary call naming the rung actually taken plus the admission bits; pair with _DEBUG_MIN_T and _DEBUG_BUDGET |
| `NINFER_TERNARY_MMA` | on | no | 0 disables every tensor-core rung, forcing the SIMT fallback (slower); diagnostic only |
| `NINFER_TERNARY_PTQ1_FAST` | on | no | 0 with a PTQ1 artifact rejects the mma rungs and is silently slower |
| `NINFER_TERNARY_KVMEM` / `NINFER_TERNARY_KVMEM_WINDOW_ASSEMBLY` / `NINFER_TERNARY_KVMEM_SEMANTIC` | **off** (each one only turns on when it is exactly `1`) | no | KVMem long-context machinery that this engine INHERITED (decouple the KV pool from the logical context, assemble the window by selection, score-based block selection). **Leave them OFF**: the default path is bit-identical to the factory behaviour, they need a matching pool/context setup, and switching them on changes readings silently (you would get a confident wrong number). Research it on your own build and after your own quality gate -- never in the shipped default. Details: `docs\引擎-模型-参数对照表.md` section 6.5. |
| `NINFER_SM_COUNT` | 170 via arch 120a | **yes** | compile-time kTargetSmCount used for wave/occupancy. 120a implies 170 (RTX 5090); other 50-series cards need -DNINFER_SM_COUNT=<their SM count> plus a rebuild. The size of the gain is NOT measured. |

## 6. Measurement invariants (violating these yields confident nonsense)

- Report the content kind with every number: the same card differs by up to 3x between highly predictable content and prose/code.
- Report the accept rate with every number. Throughput = step-rate x (1 + K x accept-rate). Step-rate belongs to the card; accept-rate belongs to the content and reproduces to the exact integer across cards.
- A/B on ONE binary whenever an env switch exists. When only a rebuild can change the value, alternate the two binaries and verify both sha256 values. Never run them sequentially and call the difference a result.
- Discard the first run after a cold start (clocks ramp), then take the median of at least three alternating runs.
- Long prompt (at least 1k tokens) and long output (at least 400 tokens), greedy decoding.
- The engine log is the authoritative source: read the req#N done line (decode X tok/s, accepted a/b (p percent), cache hit, TTFT) from the stderr log that start returns. The HTTP-side timing includes prefill and the first-token wait, so it understates decode.
- Cross-card absolute numbers are not comparable. Cross-card accept rates are.

## 7. Performance anchors -- is this machine normal?

| card | content | config | t/s | accept | source |
|---|---|---|---|---|---|
| RTX 4080 SUPER (ours, sm_89, 80 SM per gpu-probe) | counting | dflash2 K=7 | 353.8 | - | our measurement |
| RTX 4080 SUPER (ours) | prose | dflash2 K=7 | 112.1 | - | our measurement |
| RTX 4080 SUPER (ours) | counting | MTP d4 | 211.9 | - | our measurement |
| RTX 4080 SUPER (ours) | counting | no speculation | 63.7 | - | our measurement |
| RTX 5090 D (volunteer, sm_120, 32 GB) | counting | dflash2 K=7 | 512.9 | 522/533 (97.9%) | volunteer, no rebuild |
| RTX 5090 D (volunteer) | prose | dflash2 K=7 | 154.7 | 346/1763 (19.6%) | volunteer |
| RTX 5090 D (volunteer) | counting | MTP (best) | 343.8 | - | volunteer |
| RTX 5090 D (volunteer) | counting | MTP d3 (what we first shipped) | 250-268 | 447/454 -> 522/533 (98.5%, cross-card) | volunteer |

## 8. Never

- drive a .bat interactively from an agent
- trust a tie between two arms without proving the arm ran
- report a number without content kind and accept rate
- assume the engine matches the card without doctor
- enable the KVMem switches (`NINFER_TERNARY_KVMEM*`): they are off by default on purpose, and turning them on changes readings silently (see section 5)
- rebuild only `ninfer-serve` and then re-check numerics with an OLD `ninfer-perplexity`: a serve rebuild does NOT relink perplexity, and the stale binary will reproduce the old numbers and make you conclude the switch did nothing (rebuild BOTH targets in the same batch)

