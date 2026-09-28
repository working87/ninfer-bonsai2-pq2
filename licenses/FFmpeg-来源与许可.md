# FFmpeg 来源与许可（已从 GPLv3 构建换为 LGPLv3 构建）

> 落盘：2026-09-26 ｜ 适用：本包 engine\ 与 src-tree\...\ffmpeg\

## 1. 为什么有这份说明

本包**曾**附带 FFmpeg 的 **GPLv3** 构建（其二进制内嵌 banner 可查：libavcodec license: GPL version 3 or later、
configuration: --enable-gpl --enable-version3）。GPLv3 的再分发需要随包提供**对应源码**（或有效期 3 年的书面要约），
与本包的交付形态不匹配。因此**已整体替换为 LGPLv3 构建**，同一份 LGPLv3 允许以动态链接方式分发。

## 2. 现在随包的是哪一份

| 项 | 值 |
|---|---|
| 构建 | BtbN/FFmpeg-Builds ｜ fmpeg-n9.0-latest-win64-lgpl-shared-9.0 |
| 版本串 | FFmpeg version n9.0.2-8-gb135b25c19-20260925 |
| 许可 | **LGPL version 3 or later**（二进制内嵌 banner 可自验） |
| 绝对版本 | 上游 FFmpeg commit **b135b25c19**，release 线 n9.0.2 |
| 主版本对齐 | avcodec **63** / avformat **63** / avutil **61** / swscale **10** / swresample **7** / avdevice **63** / avfilter **12** |

替换前已做 **ABI 校验**：
infer-serve.exe 对这 4 个 DLL 的**全部 34 个导入符号**在新 DLL 的导出表中
**逐个命中（缺失 0）**：avcodec 11 / avformat 8 / avutil 12 / swscale 3。

## 3. 随包 DLL（engine\，替换后）

| 文件 | 大小 | SHA256（前 16 位） |
|---|---|---|
| `avcodec-63.dll` | 87 MB | 1a43cf4b22bce33d… |
| `avdevice-63.dll` | 4.7 MB | 0b4363087576ea75… |
| `avfilter-12.dll` | 29.8 MB | cc227b1ed66d3648… |
| `avformat-63.dll` | 21.7 MB | 8da0b1708a0e320a… |
| `avutil-61.dll` | 2.9 MB | 00fcd925ecd35a72… |
| `swresample-7.dll` | 0.7 MB | f63082a912994464… |
| `swscale-10.dll` | 2.2 MB | 5d941dc3791ed917… |

## 4. 源码获取（LGPL 合规）

- 构建脚本与配置：https://github.com/BtbN/FFmpeg-Builds
- 上游 FFmpeg 源码：https://github.com/FFmpeg/FFmpeg ｜ tag **n9.0.2** ｜ commit **b135b25c19**
- 镜像说明：本机 github.com 直连不通，可用 https://gh-proxy.com/https://github.com/... 前缀取用（已实测）

## 5. 许可全文

- licenses\FFmpeg-LGPLv3.txt —— GNU LESSER GENERAL PUBLIC LICENSE v3 全文（随 BtbN 包提供）
- licenses\GPL-3.0.txt —— GNU GPL v3 全文（**LGPLv3 正文明确引用 GPLv3，必须同时提供**）

> 本包以**动态链接**方式使用 FFmpeg：DLL 独立存在，用户可自行替换为修改过的版本而无需重新编译引擎。