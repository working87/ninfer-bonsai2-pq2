# AGENTS.md：给 AI Agent 的部署指令

目标：在用户的 Windows x64 + NVIDIA 机器上部署 ninfer + 三元 Bonsai-2-27B（极速档 PQ2），并验证服务可用。

原作者：**沈三殊（shensanshu）**。本仓库除模型权重外的全部内容（方案、文档、引擎改造与编译、源码树、agent 工具链、探针）都由沈三殊发布，这里只是转发。
B站 https://space.bilibili.com/85280961 ；魔搭 https://www.modelscope.cn/models/shensanshu/ninfer-ada-ternary

## 怎么部署：按原作者的指南走

**入口是 `00-从这里开始.md`**，按里面的五步契约执行：探针建档 → 选件 → 起服务 → 过四道门 → 留痕回执。
配套文件：`MUST-DO.md`、`agent\AGENT.md`（机读接口 `agent\ninfer-agent.ps1`）、`agent\must-do.json`、`gpu-probe.exe`。

本仓库和原包只有一个区别：**git 里没有大文件**（引擎 exe、ffmpeg dll、模型权重）。
在指南的「选件」这一步，按本机情况确定需要哪些，然后**到 `DOWNLOADS.md` 里找地址，缺啥下啥**，放到对应目录并核对 SHA256。

## 额外规则（转发者补充）

1. **大文件只用 `DOWNLOADS.md` 里的国内地址**（魔搭 modelscope.cn、清华镜像）。不要去 huggingface.co、GitHub Release 等海外站点下载。
2. 仓库必须放在**纯英文（ASCII）路径**下。路径里有中文时，引擎会报 `invalid UTF-8`。
3. 需要 `DOWNLOADS.md` 以外的东西（例如自己编译用的工具链）时，优先找国内镜像；找不到就停下来问用户，不要擅自从海外站点下载大文件。
