# AGENTS.md：给 AI Agent 的部署指令

目标：在用户的 Windows x64 + NVIDIA RTX 40/50 系机器上部署 ninfer + 三元 Bonsai-2-27B（极速档 PQ2），并验证服务可用。

原作者：**沈三殊（shensanshu）**。本仓库除模型权重外的全部内容（方案、脚本、文档、引擎改造与编译、源码树、agent 工具链）都由沈三殊发布，这里只是转发整理。
B站 https://space.bilibili.com/85280961 ；魔搭 https://www.modelscope.cn/models/shensanshu/ninfer-ada-ternary

## 硬性规则

1. **只用国内源**：魔搭 modelscope.cn、清华 PyPI 镜像。**不要**去 huggingface.co、GitHub Release 或其他海外站点下载任何大文件。`scripts\deploy.ps1` 里已经写好全部国内地址。
2. 仓库必须放在**纯 ASCII 路径**下（例如 `D:\ai\ninfer-pq2`）。路径里有中文时，引擎会报 `invalid UTF-8`。
3. 显卡算力只支持 **8.9（RTX 40 系）** 和 **12.0（RTX 50 系）**，显存 ≥ 10 GB。其他架构需要从源码自己编译，见 `08-从零复现方案书（兜底路线）.md`。
4. **不需要**安装 CUDA Toolkit，只需要 NVIDIA 驱动（`nvidia-smi` 能运行即可）。
5. `start-*.bat` 必须保持纯 ASCII、无 BOM，不要往里写中文。
6. 不要交互式地运行 `.bat`（会卡在 `pause`）。Agent 用 `agent\ninfer-agent.ps1`，或者先设 `NINFER_AGENT=1`。

## 一键部署

```powershell
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
```

脚本依次完成：
1. 检查路径、驱动、算力、显存、磁盘。
2. 从魔搭下载与显卡匹配的引擎和 7 个 ffmpeg dll。
3. 下载模型：显存 ≥ 15 GB 下 DFlash2 制品（10.5 GB），否则下基础制品（8.3 GB）。
4. 每个文件都做 SHA256 校验，支持断点续传，可以重复运行。
5. 缺 VC++ 运行库时，从清华镜像补。
6. 用 `agent\ninfer-agent.ps1 start` 起服务（端口 8085），发一条真实推理请求。

模型文件很大，请在后台运行并等待，不要中途打断。中断了就重跑，已校验的文件会跳过，未下完的会续传。

常用参数：`-Model base|dflash2|all`、`-Engine all`、`-Port 8096`、`-NoStart`。

## 部署后

按原作者的五步契约继续，入口是 **`00-从这里开始.md`**：
- 必做调优项：`MUST-DO.md` 和 `agent\must-do.json`。
- 机读接口：`agent\AGENT.md`，里面有 `doctor / plan / start / bench / stop` 用法和退出码表。
- 显卡档案：`gpu-probe.exe`。
- 完成的事项记录到 `agent\state.json`。

## 成功判据（三条全部满足才算成功）

- `GET http://127.0.0.1:8085/v1/models` 返回 200
- 引擎日志里出现 `listening on http://127.0.0.1:8085`
- 一次 `/v1/chat/completions` 返回正常文本。请求体**必须带** `"model":"qwen3.8-27b"`

## 故障处理

按以下顺序查：`agent\AGENT.md` §4 故障路由 → `02-排错手册 · 预案与处方.md` → `判据.txt` → `docs\复现手册-排错篇.md`。
回报问题时，必须附上三样证据：引擎 sha256 前 16 位、制品文件名、完整命令加日志原文。
