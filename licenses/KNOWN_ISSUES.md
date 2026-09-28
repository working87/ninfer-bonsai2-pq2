# Ternary Bonsai 2 27B: known issues

Last checked: 2026-09-23. Applies to `Ternary-Bonsai-2-27B` (GGUF `PQ2_0` / `PTQ1_0` / `F16`, and the MLX build).

This page lists problems we know about, with the fastest workaround first. If you hit something that is not here, please open an issue on [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp/issues) (runtime) or [PrismML-Eng/Bonsai-demo](https://github.com/PrismML-Eng/Bonsai-demo/issues) (setup scripts and demo server).

**Status labels**

- **Fixed in release**: available in a published binary release.
- **Fixed in source**: merged to the `prism` branch of PrismML-Eng/llama.cpp. It isn't in a binary release yet, so build from source or wait for the next release.
- **Fix in review**: a pull request exists and has not been merged.
- **Open**: no fix yet.

## Start here: three fixes that cover most reports

| If you see... | Do this |
|---|---|
| Empty answers, or "it thinks forever and never answers" | Give the model a large output limit: `-n 16384` or more (`max_tokens` for the API), with `-c 65536`. For shorter thinking, also send `reasoning_effort: "medium"`. |
| HTTP 500 with `reasoning_effort: "high"` | Use `"xhigh"` (the default) or `"medium"`. |
| Crash on load on an AMD Zen 4/Zen 5 or other AVX-512 CPU | See [CPU crash on load](#cpu-crash-on-load-avx-512-cpus). |

## Empty, cut-off or runaway output

**Empty or truncated answers.** The model reasons before it answers, and the reasoning counts against the output limit. If the limit runs out while it's still reasoning, you get an empty or cut-off reply. This is the most common report we see, including reports of poor output in non-English languages.
*Workaround:* `-n 16384` or higher (or `max_tokens`), with `-c 65536`. A small cap such as `-n 256` ends generation mid-thought. `reasoning_effort: "medium"` also helps: it runs out of budget far less often (see [Long reasoning](#empty-cut-off-or-runaway-output)). **Status: documented in the model card.**

**`reasoning_effort: "high"` returns HTTP 500.** The chat template accepts `low`, `medium` and `xhigh`, not `high`.
*Workaround:* use `xhigh` (the default) or `medium`. **Status: open.**

**`low` doesn't shorten reasoning much.** Although the chat template asks for brief reasoning at `low`, in our measurements it used about as many tokens as the default `xhigh`.
*Workaround:* use `medium` for shorter responses, as the model card recommends, or set a thinking budget. **Status: known behaviour.**

**`low` can still run out of output budget.** Under a tight output limit, `low` doesn't always finish.
*Workaround:* keep the output limit generous (see above). **Status: open.**

**A thinking budget in `chat_template_kwargs` is ignored.** The chat template has no thinking-budget hook, so `chat_template_kwargs.thinking_budget_tokens` has no effect and produces no error.
*Workaround:* send the budget as a top-level field of the request body, or start the server with `--reasoning-budget N`; a value in the request overrides the server flag. A budget of `0` does not turn reasoning off. To turn it off, send `reasoning_effort: "none"` with the server left at `--reasoning auto` (the default). **Status: open (documentation).**

**`--reasoning on` overrides a client's `reasoning_effort: "none"`.**
*Workaround:* leave the server at `--reasoning auto`. **Status: open.**

**Looping on some prompts at `xhigh`.** A small share of instruction-following prompts loop instead of finishing. Community reports suggest `--repeat-penalty 1.05` helps. In our tests it didn't help noticeably, and a stronger penalty tended to hurt.
*Workaround:* `reasoning_effort: "medium"`, which runs out of budget much less often. **Status: open.**

**Long reasoning.** The model tends to reason at length, which costs time and tokens even when the answer is correct.
*Workaround:* use `reasoning_effort: "medium"` or a thinking budget. When the output limit is moderate (around 16k tokens), `medium` thinks noticeably less than the default `xhigh` and is about as accurate, because `xhigh` more often runs out of budget mid-reasoning. With much larger output budgets, `xhigh` is the more accurate setting. **Status: known behaviour.**

## Sampling and metadata

**`min_p` is not in the GGUF.** The file carries `top_k=20`, `top_p=0.95` and `temperature=1.0`, but not `min_p`. The recommended value is 0.05, which is llama.cpp's own default, so llama.cpp users get it automatically.
*Workaround:* with a runtime whose default is 0.0, set `min_p` to 0.05. **Status: planned** (a metadata update to the model files will add the key).

**`presence_penalty` and `repetition_penalty` are not in the GGUF**, so a server started without options won't apply the model card's values.
*Workaround:* set them explicitly as the model card describes. **Status: open.**

**MLX build samples almost greedily.** The MLX `generation_config.json` is missing its sampling settings.
*Workaround:* pass the sampler settings explicitly (`temperature=1.0`, `top_p=0.95`, `top_k=20`). **Status: open.**

**The website and the model card list different sampling settings.** The model card is correct. **Status: open (documentation).**

**The GGUF's name field reads "Hf".** This is cosmetic, but tools that display or catalogue model metadata show the wrong name. **Status: fix in review** (a metadata update to the model files sets the name).

## Tool calling and agent loops

**Malformed tool calls.** Tool calls sometimes come out malformed or loop (for example repeated `// // //`). This is a known model limitation in structured output, and we're working on it. **Status: open.**

**HTTP 500/400 when a tool call has empty or non-JSON `arguments`.**
*Workaround:* send `"{}"` for a call with no arguments. **Status: open** ([#112](https://github.com/PrismML-Eng/llama.cpp/issues/112)).

**HTTP 500 when a system message isn't first, or when there are two.** The template requires exactly one system message, at the start.
*Workaround:* merge system messages into one leading message. **Status: open.**

**Context grows and the prompt cache misses in tool loops.** Reasoning from earlier turns is re-rendered into later ones, and tool calls are re-rendered differently from how they were generated. Each turn then re-processes most of the conversation.
*Workaround:* don't echo reasoning back into the conversation in tool loops. **Status: open** ([Bonsai-demo #183](https://github.com/PrismML-Eng/Bonsai-demo/issues/183)).

## Crashes and load failures

### CPU crash on load (AVX-512 CPUs)

**`PQ2_0` segfaults while loading on CPUs with AVX-512**, including AMD Zen 4 and Zen 5 (Ryzen AI 300 series, Strix Halo) and some server and virtualised CPUs. It crashes even with all layers offloaded to a GPU.
*Workaround:* build from source at the current `prism` branch. `--no-repack` may avoid it but is unconfirmed. **Status: fixed in source** ([#245](https://github.com/PrismML-Eng/llama.cpp/pull/245), merged 2026-09-23; reports [#180](https://github.com/PrismML-Eng/llama.cpp/issues/180), [#204](https://github.com/PrismML-Eng/llama.cpp/issues/204), [#219](https://github.com/PrismML-Eng/llama.cpp/issues/219), [Bonsai-demo #182](https://github.com/PrismML-Eng/Bonsai-demo/issues/182)).

**CUDA 13.3 builds crash on some systems.** On Linux this is a segfault; on Windows the server prints its banner and exits without a message.
*Workaround:* use the CUDA 12.8 build on Linux or the CUDA 12.4 build on Windows. **Status: open** ([#222](https://github.com/PrismML-Eng/llama.cpp/issues/222)).

**Windows CUDA builds don't start on some CPUs**; the Windows CPU-only build does.
*Workaround:* use the CPU-only build while this is investigated. **Status: open** ([#241](https://github.com/PrismML-Eng/llama.cpp/issues/241)).

**ROCm/HIP aborts on consumer RDNA2 GPUs** (for example gfx1030).
*Workaround:* none yet on HIP; try the Vulkan build. **Status: open** ([Bonsai-demo #197](https://github.com/PrismML-Eng/Bonsai-demo/issues/197)).

**`PQ2_0` produces garbled output on Windows HIP with gfx1151** (Strix Halo integrated GPU). CPU (`-ngl 0`) output is correct.
*Workaround:* `-ngl 0`, or the Vulkan build with `PTQ1_0`. **Status: open** ([#223](https://github.com/PrismML-Eng/llama.cpp/issues/223)).

**`--split-mode tensor` and `--split-mode row` can't load across two GPUs.**
*Workaround:* use the default layer split. **Status: open** ([#213](https://github.com/PrismML-Eng/llama.cpp/issues/213)).

**Older `Q2_0` files declare type 42 and won't load.**
*Workaround:* download the current files from the model repository. **Status: answered** ([#167](https://github.com/PrismML-Eng/llama.cpp/issues/167)).

### Runtimes other than the PrismML build

`PQ2_0` and `PTQ1_0` are new quantization types, and support for them isn't in mainline llama.cpp yet. That means:

- Stock llama.cpp, Ollama and LM Studio (GGUF) can't load the `PQ2_0` or `PTQ1_0` files.
- The `F16` file loads in stock llama.cpp but produces garbled output, because it depends on metadata only the PrismML build applies.

*Workaround:* use the [PrismML llama.cpp build](https://github.com/PrismML-Eng/llama.cpp/releases). **Status: open.**

**The MLX build needs its bundled loader.** MLX apps and LM Studio (MLX) can't load it yet. Support has landed upstream in mlx-vlm but isn't in a released runtime.
*Workaround:* load with the loader shipped beside the model. Also use mlx-vlm 0.7.1 or newer: 0.6.3 breaks image input when serving. **Status: open.**

**The MLX build of the 27B model has no vision support.**
*Workaround:* for image input, use the GGUF with the `mmproj` file. **Status: open.**

## Downloads, setup and building from source

**The launch-day release (`prism-b10687`) has no binaries.**
*Workaround:* use [`prism-b10709`](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10709-9a9394a) or newer, which has builds for macOS, Linux, Windows and Android. Please prefer official releases to copies shared elsewhere. **Status: fixed in release b10709** ([#183](https://github.com/PrismML-Eng/llama.cpp/issues/183), [#193](https://github.com/PrismML-Eng/llama.cpp/issues/193), [#195](https://github.com/PrismML-Eng/llama.cpp/issues/195)).

**Windows `setup.ps1` installed the Vulkan build on NVIDIA machines**, which runs far slower than CUDA and shows no error.
*Workaround:* update the demo repository, then check that the server log reports a CUDA device. **Status: fixed** ([Bonsai-demo #176](https://github.com/PrismML-Eng/Bonsai-demo/issues/176)).

**Windows `setup.ps1` downloads only `PQ2_0`.**
*Workaround:* download `PTQ1_0` manually from the model repository if you need it (for example for Vulkan). **Status: open** ([Bonsai-demo #184](https://github.com/PrismML-Eng/Bonsai-demo/issues/184)).

**`setup.sh` downloads about 19 GB of model files without asking.**
*Workaround:* set `BONSAI_SKIP_GGUF=1` to skip the download. **Status: open (documentation).**

**The default 32K context doesn't fit on 12 GB GPUs.** The demo scripts size context from system RAM, not GPU memory.
*Workaround:* set `BONSAI_CTX` to a smaller value, or `BONSAI_KV4=1`. **Status: open** ([Bonsai-demo #193](https://github.com/PrismML-Eng/Bonsai-demo/issues/193)).

**`setup.sh` fails to build on macOS 27 / Xcode 26.5.**
*Workaround:* see the patch in the issue. **Status: open** ([Bonsai-demo #177](https://github.com/PrismML-Eng/Bonsai-demo/issues/177)).

**CUDA builds from source fail with "CUDA_ARCHITECTURES is empty".**
*Workaround:* pass `-DCMAKE_CUDA_ARCHITECTURES=<your arch>` (for example `89` for RTX 40-series). **Status: open** ([#182](https://github.com/PrismML-Eng/llama.cpp/issues/182)).

**CUDA builds may need `-DGGML_CUDA_FA_ALL_QUANTS=ON`** for the quantized KV-cache types to work with flash attention. The build docs don't mention it yet. **Status: open (documentation).**

**RTX 5090: prebuilt Linux binaries decode erratically.**
*Workaround:* build from source with `-DCMAKE_CUDA_ARCHITECTURES=120a-real`. **Status: open** ([#199](https://github.com/PrismML-Eng/llama.cpp/issues/199)).

## Performance

**`q5_0` KV cache is several times slower** than the other cache types at all context depths.
*Workaround:* use `f16`, `q8_0` or `q4_0` for `-ctk`/`-ctv`. **Status: open** ([#191](https://github.com/PrismML-Eng/llama.cpp/issues/191)).

**A single conversation keeps re-processing its prompt on the server.** By default the server splits its cache across several slots, and the prompt cache is too small for long conversations.
*Workaround:* for single-user use, start the server with `-np 1 --cache-ram 24576`. **Status: open** ([Bonsai-demo #183](https://github.com/PrismML-Eng/Bonsai-demo/issues/183)).

**`PQ2_0` on Vulkan silently runs on the CPU** in the current binary release, at under 2 tokens per second. The log still reports all layers offloaded to the GPU; the tell is a `CPU model buffer size` of several GB, with almost nothing on the Vulkan device.
*Workaround:* build from source at the current `prism` branch, where `PQ2_0` runs fully on the GPU, or use `PTQ1_0`. **Status: fixed in source** ([#238](https://github.com/PrismML-Eng/llama.cpp/pull/238), merged 2026-09-21; not yet in a binary release).

**`PTQ1_0` decode on Vulkan is slower than it should be** in the current binary release: it runs on the GPU, but decodes at under 2 tokens per second on an Intel Arc B390. **Status: fixed in source for Intel GPUs that llama.cpp's Vulkan backend classes as Xe2** ([#238](https://github.com/PrismML-Eng/llama.cpp/pull/238), merged 2026-09-21; not yet in a binary release). That class includes the Xe3-based Arc B390, where it measured about 9x faster; other GPUs are unchanged so far; **further speedups in review** ([#252](https://github.com/PrismML-Eng/llama.cpp/pull/252)). Reports: [#186](https://github.com/PrismML-Eng/llama.cpp/issues/186), [#201](https://github.com/PrismML-Eng/llama.cpp/issues/201).

**`PTQ1_0` on Vulkan can hang Intel Arc GPUs** after about 1,900 tokens.
*Workaround:* run on CPU for now. **Status: open** ([#192](https://github.com/PrismML-Eng/llama.cpp/issues/192)).

**The SYCL build can't run `PQ2_0` or `PTQ1_0` yet**; it stops at load with "unsupport data type".
*Workaround:* on Intel GPUs, use the Vulkan build for now. **Status: fix in review** ([#235](https://github.com/PrismML-Eng/llama.cpp/pull/235)).

**CPU inference on consumer x86 CPUs** (AMD Zen 1–4, Intel Alder Lake and newer) doesn't use the fast `PQ2_0` kernels in current releases.
*Workaround:* build from source at the current `prism` branch for the AVX2/AVX-VNNI kernels. **Status: fixed in source for `PQ2_0`** ([#206](https://github.com/PrismML-Eng/llama.cpp/pull/206), merged 2026-09-21); **fix in review for `PTQ1_0`** ([#250](https://github.com/PrismML-Eng/llama.cpp/pull/250)).

**The Metal tensor API is not enabled on the newest Apple chips.** **Status: fixed in source** ([#196](https://github.com/PrismML-Eng/llama.cpp/pull/196), merged 2026-09-21).

**Multi-token prediction (MTP) is refused for these files.** **Status: fixed in source** ([#205](https://github.com/PrismML-Eng/llama.cpp/pull/205), merged 2026-09-21).

**`--spec-type ngram-*` has no effect on this model.** The flag is accepted but no speculation runs, so throughput reported with it is plain decoding. **Status: open** ([#203](https://github.com/PrismML-Eng/llama.cpp/issues/203)).

**`PTQ1_0` decode on CUDA.** A faster small-batch kernel is in review. **Status: fix in review** ([#218](https://github.com/PrismML-Eng/llama.cpp/pull/218)).

**AMD GPUs on HIP decode slower than expected.** **Status: fix in review** ([#116](https://github.com/PrismML-Eng/llama.cpp/pull/116)).

## Vision

**Poor results on "point at the object" (grounding) tasks with small images.**
*Workaround:* start the server with `--image-min-tokens 1024`. **Status: open (the demo server doesn't pass it yet).**

## Reported, under investigation

We haven't reproduced these yet. If you can, a report with your command line, hardware and build helps.

- Stalls between turns after tool calls on AMD ROCm (RX 9070 XT).
- Connection resets or crashes with a quantized KV cache at very long contexts (around 200K tokens).
- `download_binaries.sh` choosing the CUDA 12.8 build on CUDA 13.x systems ([Bonsai-demo #206](https://github.com/PrismML-Eng/Bonsai-demo/issues/206)).
